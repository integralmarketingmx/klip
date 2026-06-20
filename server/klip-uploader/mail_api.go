// mail_api.go: endpoints HTTP del email Klip.
//   - POST /send  : envía un correo vía Gmail DWD (multipart o JSON).
//   - GET  /inbox : devuelve las respuestas detectadas para un usuario.
//
// Ambos endpoints van protegidos con un shared secret en el header
// `X-Klip-Token` (o `Authorization: Bearer <token>`), comparado contra la env
// KLIP_API_TOKEN. Si KLIP_API_TOKEN no está seteada, los endpoints responden 503
// (mejor fallar cerrado que abrir sin protección).
//
// Credenciales Gmail en runtime: ver gmail.go (ADC + DWD, sin llave JSON).
package main

import (
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

// mailUserDefault es el usuario a impersonar por defecto en pruebas.
func mailUserDefault() string {
	return envOr("KLIP_MAIL_USER", "miguel.ibarra@integralmarketing.agency")
}

// apiToken es el shared secret esperado (env KLIP_API_TOKEN). Vacío => endpoints cerrados.
func apiToken() string { return os.Getenv("KLIP_API_TOKEN") }

// checkAPIToken valida el shared secret. Devuelve true si autorizado.
// Si no hay token configurado en el servidor, NO autoriza (fail-closed).
func checkAPIToken(r *http.Request) (ok bool, configured bool) {
	want := apiToken()
	if want == "" {
		return false, false
	}
	got := strings.TrimSpace(r.Header.Get("X-Klip-Token"))
	if got == "" {
		// También aceptamos Authorization: Bearer <token>.
		if a := r.Header.Get("Authorization"); strings.HasPrefix(a, "Bearer ") {
			got = strings.TrimSpace(strings.TrimPrefix(a, "Bearer "))
		}
	}
	return got != "" && got == want, true
}

// writeJSON serializa v como JSON con el status dado.
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// sendRequest es el payload JSON del POST /send (alternativa al multipart).
type sendRequest struct {
	From    string   `json:"from"`
	To      []string `json:"to"`
	CC      []string `json:"cc"`
	BCC     []string `json:"bcc"`
	Subject string   `json:"subject"`
	Body    string   `json:"body"`
	Slug    string   `json:"slug"`
	// AttachSlug: si se pasa, el server adjunta el PNG ya subido <slug>.png del uploadDir.
	AttachSlug string `json:"attachSlug"`
	// Method selecciona el transporte: "" o "dwd" (default), "smtp" o "oauth".
	Method string `json:"method"`
	// SMTP: config del método "smtp" (host/port/user/pass/from). Solo se usa si method=="smtp".
	SMTP *smtpConfig `json:"smtp"`
	// AccessToken: token del usuario para el método "oauth". Solo se usa si method=="oauth".
	AccessToken string `json:"accessToken"`
}

// handleSend implementa POST /send. Acepta multipart/form-data o application/json.
// Construye la lista de adjuntos (archivo subido en multipart, o referencia a un
// slug ya almacenado) y llama a sendMail.
func handleSend(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "POST only"})
		return
	}
	ok, configured := checkAPIToken(r)
	if !configured {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "KLIP_API_TOKEN no configurado en el servidor"})
		return
	}
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token inválido o ausente"})
		return
	}

	var (
		req         sendRequest
		attachments []adjunto
	)

	ct := r.Header.Get("Content-Type")
	switch {
	case strings.HasPrefix(ct, "multipart/form-data"):
		r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
		if err := r.ParseMultipartForm(maxBytes); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "multipart inválido: " + err.Error()})
			return
		}
		req.From = r.FormValue("from")
		req.To = splitRecipients(r.FormValue("to"))
		req.CC = splitRecipients(r.FormValue("cc"))
		req.BCC = splitRecipients(r.FormValue("bcc"))
		req.Subject = r.FormValue("subject")
		req.Body = r.FormValue("body")
		req.Slug = r.FormValue("slug")
		req.AttachSlug = r.FormValue("attachSlug")
		req.Method = r.FormValue("method")
		req.AccessToken = r.FormValue("accessToken")
		// Config SMTP por campos de formulario (cuando method=="smtp" y se manda multipart).
		if strings.EqualFold(r.FormValue("method"), "smtp") {
			port := 0
			if v := strings.TrimSpace(r.FormValue("smtpPort")); v != "" {
				port, _ = strconv.Atoi(v)
			}
			req.SMTP = &smtpConfig{
				Host: r.FormValue("smtpHost"),
				Port: port,
				User: r.FormValue("smtpUser"),
				Pass: r.FormValue("smtpPass"),
				From: r.FormValue("smtpFrom"),
			}
		}
		// Adjunto subido directamente (campo "file").
		if f, hdr, err := r.FormFile("file"); err == nil {
			defer f.Close()
			b, _ := io.ReadAll(f)
			if len(b) > 0 {
				attachments = append(attachments, adjunto{
					name:  hdr.Filename,
					mime:  hdr.Header.Get("Content-Type"),
					bytes: b,
				})
			}
		}
	default: // JSON
		r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "JSON inválido: " + err.Error()})
			return
		}
	}

	// from por defecto = usuario de pruebas.
	if strings.TrimSpace(req.From) == "" {
		req.From = mailUserDefault()
	}

	// Validación de payload (sin llamar a Gmail).
	if len(req.To) == 0 && len(req.CC) == 0 && len(req.BCC) == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "se requiere al menos un destinatario (to/cc/bcc)"})
		return
	}

	// Adjunto por referencia a un slug ya subido (<slug>.png en uploadDir).
	if att, ok := attachmentFromSlug(req.AttachSlug); ok {
		attachments = append(attachments, att)
	}

	method := strings.ToLower(strings.TrimSpace(req.Method))
	if method == "" {
		method = "dwd"
	}

	// Validación temprana del método "smtp": sin config válida, error claro (sin red).
	if method == "smtp" {
		if req.SMTP == nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "method=smtp requiere el bloque 'smtp' (host/port/user/pass)"})
			return
		}
		if err := req.SMTP.valid(); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
	}
	if method == "oauth" && strings.TrimSpace(req.AccessToken) == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "method=oauth requiere 'accessToken'"})
		return
	}

	// KLIP_MAIL_DRY_RUN=1 valida el payload y arma el MIME sin llamar al transporte (útil en CI).
	if os.Getenv("KLIP_MAIL_DRY_RUN") == "1" {
		if _, err := buildMIME(req.From, req.To, req.CC, req.BCC, req.Subject, req.Body, req.Slug, attachments); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "MIME inválido: " + err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "dryRun": true, "method": method, "attachments": len(attachments)})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()

	var sendErr error
	switch method {
	case "smtp":
		sendErr = sendViaSMTP(ctx, *req.SMTP, req.From, req.To, req.CC, req.BCC, req.Subject, req.Body, req.Slug, attachments)
	case "oauth":
		sendErr = sendViaOAuth(ctx, req.AccessToken, req.From, req.To, req.CC, req.BCC, req.Subject, req.Body, req.Slug, attachments)
	default: // "dwd" — comportamiento previo (Domain-Wide Delegation).
		sendErr = sendMail(ctx, req.From, req.To, req.CC, req.BCC, req.Subject, req.Body, req.Slug, attachments)
	}
	if sendErr != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": sendErr.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "method": method, "slug": sanitizeSlug(req.Slug)})
}

// handleInbox implementa GET /inbox?user=... — devuelve las respuestas detectadas.
func handleInbox(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "GET only"})
		return
	}
	ok, configured := checkAPIToken(r)
	if !configured {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "KLIP_API_TOKEN no configurado en el servidor"})
		return
	}
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token inválido o ausente"})
		return
	}

	user := strings.TrimSpace(r.URL.Query().Get("user"))
	if user == "" {
		user = mailUserDefault()
	}

	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()
	replies, err := pollReplies(ctx, user)
	if err != nil {
		// Si Gmail (DWD) falla, NO abortamos: aún podemos servir lo recibido por MX.
		// Logueamos el error y seguimos con una lista vacía de Gmail.
		log.Printf("aviso: pollReplies (Gmail) falló: %v", err)
		replies = nil
	}
	// Fusiona las respuestas de Gmail con las recibidas por nuestro MX propio
	// (inbox_store.go), deduplicadas por msgId (ver mergeReplies).
	merged := mergeReplies(replies, readAllMXReplies())
	writeJSON(w, http.StatusOK, map[string]any{"user": user, "replies": merged, "count": len(merged)})
}

// attachmentFromSlug lee <slug>.png del uploadDir y lo devuelve como adjunto.
func attachmentFromSlug(slug string) (adjunto, bool) {
	slug = sanitizeSlug(slug)
	if slug == "nilslug" || slug == "" {
		return adjunto{}, false
	}
	name := slug + ".png"
	b, err := os.ReadFile(strings.TrimRight(uploadDir, "/") + "/" + name)
	if err != nil {
		return adjunto{}, false
	}
	return adjunto{name: name, mime: "image/png", bytes: b}, true
}

// splitRecipients parte una lista de destinatarios separada por coma/; en un slice limpio.
func splitRecipients(s string) []string {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	repl := strings.NewReplacer(";", ",", "\n", ",")
	parts := strings.Split(repl.Replace(s), ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if t := strings.TrimSpace(p); t != "" {
			out = append(out, t)
		}
	}
	return out
}
