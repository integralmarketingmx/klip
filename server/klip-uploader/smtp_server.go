// smtp_server.go: receptor SMTP del INBOX por MX propio (Sprint 4 completo).
//
// Recibe respuestas dirigidas a direcciones klip+<slug>@<dominio>, las parsea,
// correlaciona por slug y las persiste vía inbox_store.go para que /inbox las
// sirva junto con las leídas por Gmail (DWD).
//
// ARRANQUE: solo se levanta si KLIP_MX_DOMAIN está seteado (ver main.go). Así no
// rompe el deploy actual que no tiene MX.
//
// ENV:
//   - KLIP_MX_DOMAIN : dominio que recibe el MX (p.ej. "klip.integralmarketing.agency").
//                      Obligatorio para arrancar el SMTP.
//   - KLIP_SMTP_ADDR : dirección de escucha del SMTP (default ":25").
//
// SIN AUTH: es recepción entrante de MX (correo de terceros), no se autentica.
// Se rechaza (550) cualquier destinatario que no matchee klip+<slug>@... o
// <algo>@<KLIP_MX_DOMAIN>.
package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"regexp"
	"strings"
	"time"

	gomail "github.com/emersion/go-message/mail"
	smtp "github.com/emersion/go-smtp"
)

// smtpMaxBytes es el límite de tamaño por mensaje (~25MB, alineado con maxBytes).
const smtpMaxBytes = 25 << 20

// reRcptSlug captura el slug en una dirección estilo klip+<slug>@dominio.
// Case-insensitive sobre el local-part "klip".
var reRcptSlug = regexp.MustCompile(`(?i)^klip\+([A-Za-z0-9_-]+)@`)

// reSubjectToken extrae el slug del token [klip#<slug>] en el asunto.
// Tolera prefijos Re:/RE:/Fwd: porque solo busca el token, no el inicio.
var reSubjectTokenMX = regexp.MustCompile(`(?i)\[klip#([A-Za-z0-9_-]+)\]`)

// mxDomain devuelve el dominio del MX propio (env KLIP_MX_DOMAIN). Vacío = SMTP off.
func mxDomain() string { return strings.ToLower(strings.TrimSpace(envOr("KLIP_MX_DOMAIN", ""))) }

// smtpAddr devuelve la dirección de escucha del receptor SMTP.
func smtpAddr() string { return envOr("KLIP_SMTP_ADDR", ":25") }

// newSMTPServer construye el receptor SMTP para `addr`/`domain` y devuelve dos closures:
//   start    — bloquea sirviendo (se llama en una goroutine); devuelve nil en cierre limpio.
//   shutdown — cierra el servidor de forma graceful (drena conexiones hasta el ctx).
// Mantener el tipo *smtp.Server contenido aquí evita filtrar el import a main.go.
func newSMTPServer(addr, domain string) (start func() error, shutdown func(context.Context) error) {
	be := &klipBackend{domain: strings.ToLower(domain)}
	s := smtp.NewServer(be)
	s.Addr = addr
	s.Domain = domain
	s.ReadTimeout = 60 * time.Second
	s.WriteTimeout = 60 * time.Second
	s.MaxMessageBytes = smtpMaxBytes
	s.MaxRecipients = 50
	s.AllowInsecureAuth = true // sin TLS obligatorio: es recepción entrante de MX

	start = func() error {
		log.Printf("klip-smtp escuchando en %s para dominio %s", addr, domain)
		if err := s.ListenAndServe(); err != nil && err != smtp.ErrServerClosed {
			return err
		}
		return nil
	}
	shutdown = func(ctx context.Context) error { return s.Shutdown(ctx) }
	return start, shutdown
}

// klipBackend implementa smtp.Backend: crea una sesión por conexión.
type klipBackend struct {
	domain string
}

func (b *klipBackend) NewSession(_ *smtp.Conn) (smtp.Session, error) {
	return &klipSession{domain: b.domain}, nil
}

// klipSession acumula el estado de un mensaje (remitente, destinatarios, slug).
type klipSession struct {
	domain string
	from   string
	slug   string // slug correlacionado por el destinatario klip+<slug>@
}

// Reset descarta el mensaje en curso (RSET / inicio de nuevo mensaje).
func (s *klipSession) Reset() {
	s.from = ""
	s.slug = ""
}

// Logout libera recursos al cerrar la sesión.
func (s *klipSession) Logout() error { return nil }

// Mail registra el return-path (MAIL FROM). Aceptamos cualquier remitente.
func (s *klipSession) Mail(from string, _ *smtp.MailOptions) error {
	s.from = from
	return nil
}

// Rcpt valida el destinatario (RCPT TO). Solo aceptamos:
//   - klip+<slug>@...  → extraemos el slug.
//   - <algo>@<KLIP_MX_DOMAIN> → aceptado (slug se intentará por header/asunto).
// Cualquier otro destinatario se rechaza con 550.
func (s *klipSession) Rcpt(to string, _ *smtp.RcptOptions) error {
	addr := strings.ToLower(strings.TrimSpace(to))

	// Caso 1: klip+<slug>@... (la señal más confiable de correlación).
	if m := reRcptSlug.FindStringSubmatch(addr); m != nil {
		s.slug = sanitizeSlug(m[1])
		return nil
	}

	// Caso 2: cualquier buzón del dominio del MX propio.
	if s.domain != "" {
		if at := strings.LastIndexByte(addr, '@'); at >= 0 {
			if addr[at+1:] == s.domain {
				return nil
			}
		}
	}

	// Resto: rechazado.
	return &smtp.SMTPError{
		Code:         550,
		EnhancedCode: smtp.EnhancedCode{5, 1, 1},
		Message:      "destinatario no aceptado por Klip",
	}
}

// Data recibe el cuerpo del mensaje, lo parsea, correlaciona el slug y persiste.
func (s *klipSession) Data(r io.Reader) error {
	// Límite duro de lectura por seguridad (además del MaxMessageBytes del server).
	lr := io.LimitReader(r, smtpMaxBytes+1)
	reply, err := parseInboundMail(lr, s.slug)
	if err != nil {
		log.Printf("klip-smtp: error parseando mensaje: %v", err)
		// 451: error temporal del lado servidor; el remitente puede reintentar.
		return &smtp.SMTPError{Code: 451, Message: "error procesando mensaje"}
	}
	if reply.Slug == "" || reply.Slug == "nilslug" {
		// Sin slug correlacionable: lo descartamos pero aceptamos el correo (250)
		// para no generar bounces. Se loguea para diagnóstico.
		log.Printf("klip-smtp: mensaje de %s sin slug correlacionable; descartado", reply.From)
		return nil
	}
	if reply.From == "" {
		reply.From = s.from
	}
	if err := appendReply(reply); err != nil {
		log.Printf("klip-smtp: no se pudo persistir reply de slug %s: %v", reply.Slug, err)
		return &smtp.SMTPError{Code: 451, Message: "error guardando mensaje"}
	}
	log.Printf("klip-smtp: reply guardado slug=%s from=%s hasImage=%v", reply.Slug, reply.From, reply.HasImage)
	return nil
}

// parseInboundMail parsea el correo entrante y lo convierte en un mxReply.
// `rcptSlug` es el slug ya extraído del destinatario (klip+<slug>@), señal #1.
// Si está vacío, se intenta correlacionar por In-Reply-To/References (#2) y por
// el token [klip#<slug>] del asunto (#3).
func parseInboundMail(r io.Reader, rcptSlug string) (mxReply, error) {
	mr, err := gomail.CreateReader(r)
	if err != nil {
		return mxReply{}, err
	}

	hdr := mr.Header

	// Remitente.
	from := ""
	if addrs, e := hdr.AddressList("From"); e == nil && len(addrs) > 0 {
		from = addrs[0].String()
	} else {
		from = strings.TrimSpace(hdr.Get("From"))
	}

	// Asunto.
	subject, _ := hdr.Subject()

	// Fecha (header crudo si el parseo falla).
	date := strings.TrimSpace(hdr.Get("Date"))

	// Message-ID del correo entrante (para dedupe).
	msgID := strings.Trim(strings.TrimSpace(hdr.Get("Message-Id")), "<>")

	// Correlación de slug por las tres señales (en orden de confianza).
	slug := sanitizeSlug(rcptSlug)
	if slug == "" || slug == "nilslug" {
		slug = ""
	}
	if slug == "" {
		// #2: In-Reply-To / References con el Message-ID determinista por slug.
		for _, key := range []string{"In-Reply-To", "References"} {
			if m := reSlugFromMsgID.FindStringSubmatch(hdr.Get(key)); m != nil {
				slug = m[1]
				break
			}
		}
	}
	if slug == "" {
		// #3: token [klip#<slug>] en el asunto (tolera Re:/RE:/Fwd:).
		if m := reSubjectTokenMX.FindStringSubmatch(subject); m != nil {
			slug = m[1]
		}
	}
	slug = sanitizeSlug(slug)

	// Recorre las partes: junta el texto y guarda imágenes adjuntas.
	var bodyText strings.Builder
	var images []string
	hasImage := false
	imgIdx := 0

	for {
		p, e := mr.NextPart()
		if e == io.EOF {
			break
		}
		if e != nil {
			// Error de parte (charset/encoding desconocido o stream malformado): detenemos el
			// recorrido. Antes hacía `continue`, que ante un error persistente (sin avanzar el
			// reader) podía entrar en bucle infinito. Logueamos para diagnóstico.
			log.Printf("klip-smtp: parte MIME ilegible para slug %s: %v", slug, e)
			break
		}
		switch h := p.Header.(type) {
		case *gomail.InlineHeader:
			ct, _, _ := h.ContentType()
			if strings.HasPrefix(ct, "text/plain") || bodyText.Len() == 0 {
				if b, e := io.ReadAll(io.LimitReader(p.Body, 1<<20)); e == nil {
					if bodyText.Len() > 0 {
						bodyText.WriteString("\n")
					}
					bodyText.Write(b)
				}
			} else {
				_, _ = io.Copy(io.Discard, p.Body)
			}
		case *gomail.AttachmentHeader:
			ct, _, _ := h.ContentType()
			if strings.HasPrefix(strings.ToLower(ct), "image/") {
				hasImage = true
				if slug != "" && slug != "nilslug" {
					if name, e := saveReplyImage(slug, imgIdx, ct, p.Body); e == nil {
						images = append(images, name)
						imgIdx++
					} else {
						_, _ = io.Copy(io.Discard, p.Body)
					}
				} else {
					_, _ = io.Copy(io.Discard, p.Body)
				}
			} else {
				_, _ = io.Copy(io.Discard, p.Body)
			}
		default:
			_, _ = io.Copy(io.Discard, p.Body)
		}
	}

	snippet := makeSnippet(bodyText.String())

	return mxReply{
		Slug:     slug,
		From:     from,
		Subject:  strings.TrimSpace(subject),
		Snippet:  snippet,
		Date:     date,
		HasImage: hasImage,
		Source:   "mx",
		MsgID:    msgID,
		Images:   images,
	}, nil
}

// makeSnippet recorta el cuerpo a un extracto corto de una línea (~200 chars).
func makeSnippet(body string) string {
	body = strings.TrimSpace(body)
	body = strings.Join(strings.Fields(body), " ") // colapsa saltos/espacios
	const max = 200
	if len(body) > max {
		return body[:max] + "…"
	}
	return body
}

// imageExtFromMIME mapea un content-type de imagen a una extensión de archivo.
func imageExtFromMIME(ct string) string {
	ct = strings.ToLower(ct)
	switch {
	case strings.Contains(ct, "jpeg"), strings.Contains(ct, "jpg"):
		return ".jpg"
	case strings.Contains(ct, "png"):
		return ".png"
	case strings.Contains(ct, "gif"):
		return ".gif"
	case strings.Contains(ct, "webp"):
		return ".webp"
	default:
		return ".img"
	}
}

// saveReplyImage guarda una imagen adjunta de una respuesta como
// <slug>.reply-<idx><ext> en el uploadDir y devuelve el nombre de archivo.
func saveReplyImage(slug string, idx int, ct string, body io.Reader) (string, error) {
	ext := imageExtFromMIME(ct)
	name := fmt.Sprintf("%s.reply-%d%s", sanitizeSlug(slug), idx, ext)
	dst, err := createUploadFile(name)
	if err != nil {
		return "", err
	}
	defer dst.Close()
	if _, err := io.Copy(dst, io.LimitReader(body, smtpMaxBytes)); err != nil {
		return "", err
	}
	return name, nil
}
