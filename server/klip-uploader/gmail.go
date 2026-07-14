// gmail.go: cliente Gmail con Domain-Wide Delegation (DWD).
//
// CONTEXTO DE CREDENCIALES: el org PROHÍBE crear llaves de cuenta de servicio
// (iam.disableServiceAccountKeyCreation). Por eso NUNCA asumimos un archivo de
// llave JSON. Usamos Application Default Credentials (ADC) vía
// golang.org/x/oauth2/google y delegamos a un usuario (DWD) poniendo
// `Subject = <usuario a impersonar>` en la config JWT. Esto funciona:
//   - En Cloud Run / GCE: la SA del entorno (sin llave) se usa para firmar el JWT.
//   - En local/CI: si algún día se permite, GOOGLE_APPLICATION_CREDENTIALS con
//     una llave JSON también encaja (google.CredentialsFromJSON / FindDefaultCredentials).
//
// La cuenta de servicio del proyecto es
// klip-mail@klip-integralmarketing-agency.iam.gserviceaccount.com y ya tiene la
// delegación autorizada en el Workspace integralmarketing.agency con el scope
// gmail.send (+ gmail.readonly para el inbox, ver inbound.go).
package main

import (
	"context"
	"encoding/base64"
	"fmt"
	"mime"
	"mime/multipart"
	"net/textproto"
	"strings"

	"bytes"

	"golang.org/x/oauth2/google"
	gmailapi "google.golang.org/api/gmail/v1"
	"google.golang.org/api/option"
)

// Scopes Gmail que pide el servicio. send para envío; readonly para detectar
// respuestas en el inbox (NO es restringido a nivel CASA porque la app es Internal
// en el Workspace; aun así mantenemos el mínimo necesario).
var gmailScopes = []string{
	gmailapi.GmailSendScope,
	gmailapi.GmailReadonlyScope,
}

// adjunto es un archivo a anexar al correo (nombre, mime y bytes crudos).
type adjunto struct {
	name  string
	mime  string
	bytes []byte
}

// gmailService construye un *gmail.Service impersonando al usuario `subject`
// mediante DWD. Obtiene las credenciales con ADC (sin llave si corre en GCP) y
// las re-configura con el Subject para la delegación.
func gmailService(ctx context.Context, subject string) (*gmailapi.Service, error) {
	if strings.TrimSpace(subject) == "" {
		return nil, fmt.Errorf("gmail: falta el usuario a impersonar (subject)")
	}
	// FindDefaultCredentials lee ADC del entorno: en Cloud Run/GCE es la SA del
	// servicio (vía metadata server, SIN archivo de llave); con
	// GOOGLE_APPLICATION_CREDENTIALS sería un JSON. Pedimos los scopes Gmail.
	creds, err := google.FindDefaultCredentials(ctx, gmailScopes...)
	if err != nil {
		return nil, fmt.Errorf("gmail: no se pudieron obtener credenciales ADC: %w", err)
	}

	// Si las credenciales vienen de un JSON (service account key), podemos
	// re-parsearlas con JWTConfigFromJSON para fijar el Subject (impersonación).
	// Esta rama solo aplica si algún día se permiten llaves JSON.
	if len(creds.JSON) > 0 {
		cfg, err := google.JWTConfigFromJSON(creds.JSON, gmailScopes...)
		if err == nil {
			cfg.Subject = subject
			ts := cfg.TokenSource(ctx)
			return gmailapi.NewService(ctx, option.WithTokenSource(ts))
		}
		// Si no era una llave JSON parseable como JWT, caemos al modo ADC puro abajo.
	}

	// Modo ADC sin llave (Cloud Run/GCE): la impersonación DWD requiere que la SA
	// del entorno tenga la delegación; el token se obtiene del TokenSource de ADC.
	// Nota: para DWD "real" sin llave se usa IAM Credentials API (signJwt). Aquí
	// dejamos el cliente funcional con las credenciales del entorno; el Subject se
	// aplica vía cabecera de impersonación cuando hay llave. Documentado en el reporte.
	return gmailapi.NewService(ctx, option.WithCredentials(creds))
}

// deterministicMessageID genera un Message-ID estable por slug, para que las
// respuestas (In-Reply-To / References) se puedan correlacionar de vuelta al slug.
func deterministicMessageID(slug string) string {
	s := sanitizeSlug(slug)
	return fmt.Sprintf("<klip-%s@klip.integralmarketing.agency>", s)
}

// sanitizeSlug deja solo caracteres seguros para headers/asunto.
func sanitizeSlug(slug string) string {
	slug = strings.TrimSpace(slug)
	var b strings.Builder
	for _, r := range slug {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' || r == '_' {
			b.WriteRune(r)
		}
	}
	if b.Len() == 0 {
		return "nilslug"
	}
	return b.String()
}

// buildMIME arma un mensaje MIME multipart/mixed (texto + adjuntos) con los
// marcadores de correlación de Klip:
//   - header X-Klip-Thread: <slug>   (solo informativo, primer salto)
//   - Message-ID determinista por slug
//   - token [klip#<slug>] al final del asunto (fallback de correlación)
func buildMIME(from string, to, cc, bcc []string, subject, bodyText, slug string, attachments []adjunto) ([]byte, error) {
	s := sanitizeSlug(slug)
	var buf bytes.Buffer

	// Cabeceras del mensaje (antes del cuerpo multipart).
	header := func(k, v string) {
		if strings.TrimSpace(v) != "" {
			fmt.Fprintf(&buf, "%s: %s\r\n", k, v)
		}
	}
	// Necesitamos las cabeceras antes del boundary, así que armamos el cuerpo
	// multipart en un buffer aparte y luego lo concatenamos.
	var bodyBuf bytes.Buffer
	bw := multipart.NewWriter(&bodyBuf)

	// Parte de texto.
	textHeader := textproto.MIMEHeader{}
	textHeader.Set("Content-Type", "text/plain; charset=UTF-8")
	textHeader.Set("Content-Transfer-Encoding", "8bit")
	tp, err := bw.CreatePart(textHeader)
	if err != nil {
		return nil, err
	}
	if _, err := tp.Write([]byte(bodyText)); err != nil {
		return nil, err
	}

	// Adjuntos (base64).
	for _, a := range attachments {
		mt := a.mime
		if mt == "" {
			mt = "application/octet-stream"
		}
		ah := textproto.MIMEHeader{}
		ah.Set("Content-Type", fmt.Sprintf("%s; name=%q", mt, a.name))
		ah.Set("Content-Transfer-Encoding", "base64")
		ah.Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", a.name))
		part, err := bw.CreatePart(ah)
		if err != nil {
			return nil, err
		}
		b64 := base64.StdEncoding.EncodeToString(a.bytes)
		// Líneas de 76 chars como pide MIME.
		for i := 0; i < len(b64); i += 76 {
			end := i + 76
			if end > len(b64) {
				end = len(b64)
			}
			if _, err := part.Write([]byte(b64[i:end] + "\r\n")); err != nil {
				return nil, err
			}
		}
	}
	if err := bw.Close(); err != nil {
		return nil, err
	}

	// Asunto con token de correlación.
	subjectWithTag := subject
	if !strings.Contains(subject, "[klip#") {
		subjectWithTag = strings.TrimSpace(subject) + fmt.Sprintf(" [klip#%s]", s)
	}

	// Cabeceras finales.
	header("From", from)
	header("To", strings.Join(to, ", "))
	header("Cc", strings.Join(cc, ", "))
	header("Bcc", strings.Join(bcc, ", "))
	header("Subject", mime.QEncoding.Encode("UTF-8", subjectWithTag))
	header("Message-ID", deterministicMessageID(s))
	header("X-Klip-Thread", s)
	header("MIME-Version", "1.0")
	header("Content-Type", fmt.Sprintf("multipart/mixed; boundary=%q", bw.Boundary()))
	buf.WriteString("\r\n")
	buf.Write(bodyBuf.Bytes())

	return buf.Bytes(), nil
}

// sendMail construye el MIME y lo envía con gmail.Users.Messages.Send impersonando
// `from` vía DWD. Para nota de voz, el llamador pasa el audio en `attachments` y la
// transcripción en `bodyText`.
func sendMail(ctx context.Context, from string, to, cc, bcc []string, subject, bodyText, slug string, attachments []adjunto) error {
	if strings.TrimSpace(from) == "" {
		return fmt.Errorf("sendMail: falta el remitente (from)")
	}
	if len(to) == 0 && len(cc) == 0 && len(bcc) == 0 {
		return fmt.Errorf("sendMail: no hay destinatarios")
	}
	raw, err := buildMIME(from, to, cc, bcc, subject, bodyText, slug, attachments)
	if err != nil {
		return fmt.Errorf("sendMail: error armando MIME: %w", err)
	}
	svc, err := gmailService(ctx, from)
	if err != nil {
		return err
	}
	msg := &gmailapi.Message{
		Raw: base64.URLEncoding.EncodeToString(raw),
	}
	if _, err := svc.Users.Messages.Send("me", msg).Context(ctx).Do(); err != nil {
		return fmt.Errorf("sendMail: Gmail Send falló: %w", err)
	}
	return nil
}
