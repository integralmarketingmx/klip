// gmail_oauth.go: método de envío "oauth" del endpoint POST /send.
//
// El app obtiene (vía OAuth de escritorio, ver GoogleOAuthClient.swift) un access
// token del PROPIO usuario con scope gmail.send y lo manda en la request. Aquí lo
// usamos directamente contra la Gmail API (Users.Messages.Send con "me"), SIN DWD:
// el correo sale de la cuenta del usuario que inició sesión.
//
// El access token es de corta vida (~1h); el refresh token vive CIFRADO en el app
// (SecretStore .googleOAuth) y el app renueva el access token antes de cada envío.
package main

import (
	"context"
	"encoding/base64"
	"fmt"
	"strings"

	"golang.org/x/oauth2"
	gmailapi "google.golang.org/api/gmail/v1"
	"google.golang.org/api/option"
)

// sendViaOAuth arma el MIME y lo envía con el access token del usuario.
func sendViaOAuth(ctx context.Context, accessToken, from string, to, cc, bcc []string, subject, bodyText, slug string, attachments []adjunto) error {
	if strings.TrimSpace(accessToken) == "" {
		return fmt.Errorf("oauth: falta el access token del usuario")
	}
	if strings.TrimSpace(from) == "" {
		return fmt.Errorf("oauth: falta el remitente (from)")
	}
	raw, err := buildMIME(from, to, cc, bcc, subject, bodyText, slug, attachments)
	if err != nil {
		return fmt.Errorf("oauth: error armando MIME: %w", err)
	}

	// TokenSource estático con el access token entregado por el app.
	ts := oauth2.StaticTokenSource(&oauth2.Token{AccessToken: accessToken})
	svc, err := gmailapi.NewService(ctx, option.WithTokenSource(ts))
	if err != nil {
		return fmt.Errorf("oauth: no se pudo crear el cliente Gmail: %w", err)
	}
	msg := &gmailapi.Message{Raw: base64.URLEncoding.EncodeToString(raw)}
	if _, err := svc.Users.Messages.Send("me", msg).Context(ctx).Do(); err != nil {
		return fmt.Errorf("oauth: Gmail Send falló (¿token expirado o scope insuficiente?): %w", err)
	}
	return nil
}
