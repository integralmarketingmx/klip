// inbound.go: base del INBOX (Sprint 4 parcial, sin depender de MX propio todavía).
//
// Estrategia: con Gmail API (users.messages.list impersonando al usuario vía DWD)
// traemos las respuestas que correspondan a hilos Klip y las correlacionamos por
// slug usando tres señales (en orden de confianza):
//  1. In-Reply-To / References → contienen el Message-ID determinista <klip-<slug>@…>.
//  2. Header X-Klip-Thread (solo presente en el primer salto).
//  3. Token [klip#<slug>] en el asunto (fallback).
//
// La ingestión por MX propio (buzón klip+<slug>@dominio) es Sprint 4 completo y
// NO se implementa aquí; este endpoint usa la API de Gmail del propio usuario.
package main

import (
	"context"
	"fmt"
	"regexp"
	"strings"

	gmailapi "google.golang.org/api/gmail/v1"
)

// Reply es una respuesta entrante detectada y correlacionada a un slug Klip.
type Reply struct {
	Slug     string `json:"slug"`
	From     string `json:"from"`
	Snippet  string `json:"snippet"`
	Date     string `json:"date"`     // valor crudo del header Date
	HasImage bool   `json:"hasImage"` // true si el mensaje trae adjuntos de imagen
	MsgID    string `json:"msgId"`    // id de Gmail (para depurar / dedupe)
	Source   string `json:"source"`   // "gmail" (DWD) o "mx" (receptor SMTP propio)
}

// reSlugFromMsgID extrae el slug del Message-ID determinista <klip-<slug>@…>.
var reSlugFromMsgID = regexp.MustCompile(`klip-([A-Za-z0-9_-]+)@`)

// reSlugFromSubject extrae el slug del token [klip#<slug>] en el asunto.
var reSlugFromSubject = regexp.MustCompile(`\[klip#([A-Za-z0-9_-]+)\]`)

// pollReplies trae las respuestas Klip del buzón de `user` (impersonado vía DWD),
// las correlaciona por slug y devuelve las que pudo asociar. Best-effort: si un
// mensaje no se puede leer, se omite.
func pollReplies(ctx context.Context, user string) ([]Reply, error) {
	svc, err := gmailService(ctx, user)
	if err != nil {
		return nil, err
	}

	// Buscamos por el token del asunto o por la etiqueta Klip (si el usuario la usa).
	const query = `"klip#" OR label:Klip`
	list, err := svc.Users.Messages.List("me").Q(query).MaxResults(50).Context(ctx).Do()
	if err != nil {
		return nil, fmt.Errorf("pollReplies: list falló: %w", err)
	}

	replies := make([]Reply, 0, len(list.Messages))
	for _, ref := range list.Messages {
		msg, err := svc.Users.Messages.Get("me", ref.Id).
			Format("metadata").
			MetadataHeaders("From", "Subject", "Date", "In-Reply-To", "References", "X-Klip-Thread").
			Context(ctx).Do()
		if err != nil {
			continue // best-effort
		}
		r, ok := correlateReply(msg)
		if !ok {
			continue
		}
		replies = append(replies, r)
	}
	return replies, nil
}

// correlateReply intenta sacar el slug de un mensaje usando las tres señales.
func correlateReply(msg *gmailapi.Message) (Reply, bool) {
	h := map[string]string{}
	if msg.Payload != nil {
		for _, hdr := range msg.Payload.Headers {
			h[strings.ToLower(hdr.Name)] = hdr.Value
		}
	}

	slug := ""
	// 1) In-Reply-To / References con el Message-ID determinista.
	for _, key := range []string{"in-reply-to", "references"} {
		if m := reSlugFromMsgID.FindStringSubmatch(h[key]); m != nil {
			slug = m[1]
			break
		}
	}
	// 2) X-Klip-Thread (primer salto).
	if slug == "" {
		if v := strings.TrimSpace(h["x-klip-thread"]); v != "" {
			slug = sanitizeSlug(v)
		}
	}
	// 3) Token [klip#<slug>] en el asunto (fallback).
	if slug == "" {
		if m := reSlugFromSubject.FindStringSubmatch(h["subject"]); m != nil {
			slug = m[1]
		}
	}
	if slug == "" {
		return Reply{}, false
	}

	return Reply{
		Slug:     sanitizeSlug(slug),
		From:     h["from"],
		Snippet:  msg.Snippet,
		Date:     h["date"],
		HasImage: messageHasImage(msg),
		MsgID:    msg.Id,
		Source:   "gmail",
	}, true
}

// messageHasImage revisa los MIME parts en busca de adjuntos de imagen.
func messageHasImage(msg *gmailapi.Message) bool {
	if msg.Payload == nil {
		return false
	}
	var walk func(p *gmailapi.MessagePart) bool
	walk = func(p *gmailapi.MessagePart) bool {
		if p == nil {
			return false
		}
		if strings.HasPrefix(strings.ToLower(p.MimeType), "image/") {
			return true
		}
		for _, c := range p.Parts {
			if walk(c) {
				return true
			}
		}
		return false
	}
	return walk(msg.Payload)
}
