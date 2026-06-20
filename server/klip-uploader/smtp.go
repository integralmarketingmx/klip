// smtp.go: método de envío "SMTP" del endpoint POST /send.
//
// Cuando la request trae method:"smtp" con la config SMTP (host/port/user/pass/from),
// armamos el MISMO MIME que el camino DWD (reusando buildMIME) y lo entregamos por
// SMTP estándar con STARTTLS usando net/smtp de la stdlib (sin dependencias nuevas).
//
// TRADE-OFF de seguridad documentado: la contraseña SMTP viaja del app al backend
// dentro de la request (protegida solo por HTTPS/TLS de la conexión y por el shared
// secret KLIP_API_TOKEN). El backend NO la persiste: la usa en memoria para el envío
// y la descarta. En el app la contraseña vive CIFRADA en SecretStore. Si se prefiere
// que la pass nunca salga del Mac, habría que mover el SMTP al lado del app; aquí se
// eligió el backend para reutilizar buildMIME y mantener una sola ruta /send.
package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"net"
	"net/smtp"
	"strconv"
	"strings"
	"time"
)

// smtpConfig son los datos SMTP que el app manda en la request.
type smtpConfig struct {
	Host string `json:"host"`
	Port int    `json:"port"`
	User string `json:"user"`
	Pass string `json:"pass"`
	From string `json:"from"`
}

// valid revisa que la config mínima esté presente.
func (c smtpConfig) valid() error {
	if strings.TrimSpace(c.Host) == "" {
		return fmt.Errorf("smtp: falta el host")
	}
	if c.Port <= 0 {
		return fmt.Errorf("smtp: puerto inválido")
	}
	if strings.TrimSpace(c.User) == "" {
		return fmt.Errorf("smtp: falta el usuario")
	}
	if strings.TrimSpace(c.Pass) == "" {
		return fmt.Errorf("smtp: falta la contraseña")
	}
	return nil
}

// sendViaSMTP arma el MIME y lo entrega por SMTP con STARTTLS. El `from` del sobre
// (MAIL FROM) usa cfg.From si viene, si no el `from` del mensaje.
func sendViaSMTP(ctx context.Context, cfg smtpConfig, from string, to, cc, bcc []string, subject, bodyText, slug string, attachments []adjunto) error {
	if err := cfg.valid(); err != nil {
		return err
	}
	if err := assertPublicSMTPHost(cfg.Host); err != nil {
		return err
	}
	envelopeFrom := strings.TrimSpace(cfg.From)
	if envelopeFrom == "" {
		envelopeFrom = from
	}
	if envelopeFrom == "" {
		envelopeFrom = cfg.User
	}

	raw, err := buildMIME(envelopeFrom, to, cc, bcc, subject, bodyText, slug, attachments)
	if err != nil {
		return fmt.Errorf("smtp: error armando MIME: %w", err)
	}

	// Lista completa de destinatarios del sobre (to + cc + bcc).
	rcpts := make([]string, 0, len(to)+len(cc)+len(bcc))
	rcpts = append(rcpts, to...)
	rcpts = append(rcpts, cc...)
	rcpts = append(rcpts, bcc...)
	if len(rcpts) == 0 {
		return fmt.Errorf("smtp: no hay destinatarios")
	}

	addr := net.JoinHostPort(cfg.Host, strconv.Itoa(cfg.Port))
	auth := smtp.PlainAuth("", cfg.User, cfg.Pass, cfg.Host)

	// Conexión con timeout (respeta el ctx del request).
	d := net.Dialer{Timeout: 30 * time.Second}
	conn, err := d.DialContext(ctx, "tcp", addr)
	if err != nil {
		return fmt.Errorf("smtp: no se pudo conectar a %s: %w", addr, err)
	}
	defer conn.Close()

	client, err := smtp.NewClient(conn, cfg.Host)
	if err != nil {
		return fmt.Errorf("smtp: handshake falló: %w", err)
	}
	defer client.Close()

	// STARTTLS (requerido en puertos como 587). Si el server no lo soporta, error claro.
	if ok, _ := client.Extension("STARTTLS"); ok {
		tlsCfg := &tls.Config{ServerName: cfg.Host, MinVersion: tls.VersionTLS12}
		if err := client.StartTLS(tlsCfg); err != nil {
			return fmt.Errorf("smtp: STARTTLS falló: %w", err)
		}
	} else {
		return fmt.Errorf("smtp: el servidor no soporta STARTTLS (puerto %d)", cfg.Port)
	}

	if ok, _ := client.Extension("AUTH"); ok {
		if err := client.Auth(auth); err != nil {
			return fmt.Errorf("smtp: autenticación falló (revisa usuario/contraseña): %w", err)
		}
	}

	if err := client.Mail(envelopeFrom); err != nil {
		return fmt.Errorf("smtp: MAIL FROM falló: %w", err)
	}
	for _, rcpt := range rcpts {
		if err := client.Rcpt(rcpt); err != nil {
			return fmt.Errorf("smtp: RCPT TO %s falló: %w", rcpt, err)
		}
	}
	wc, err := client.Data()
	if err != nil {
		return fmt.Errorf("smtp: DATA falló: %w", err)
	}
	if _, err := wc.Write(raw); err != nil {
		_ = wc.Close()
		return fmt.Errorf("smtp: escritura del mensaje falló: %w", err)
	}
	if err := wc.Close(); err != nil {
		return fmt.Errorf("smtp: cierre del mensaje falló: %w", err)
	}
	return client.Quit()
}

// assertPublicSMTPHost rechaza hosts SMTP que resuelven a direcciones NO enrutables públicamente
// (loopback, privadas, link-local, unspecified). Es defensa en profundidad: el método "smtp" deja
// al usuario (autenticado por token) elegir host/puerto; sin esto, un token comprometido podría
// usar el backend para sondear o alcanzar servicios internos de la red (SSRF). Nota: hay una
// ventana TOCTOU entre esta resolución y el Dial; aceptable para este nivel de mitigación.
func assertPublicSMTPHost(host string) error {
	h := strings.TrimSpace(host)
	if h == "" {
		return fmt.Errorf("smtp: host vacío")
	}
	var ips []net.IP
	if ip := net.ParseIP(h); ip != nil {
		ips = []net.IP{ip}
	} else {
		resolved, err := net.LookupIP(h)
		if err != nil {
			return fmt.Errorf("smtp: no se pudo resolver el host %q: %w", h, err)
		}
		ips = resolved
	}
	for _, ip := range ips {
		if ip.IsLoopback() || ip.IsPrivate() || ip.IsUnspecified() ||
			ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() {
			return fmt.Errorf("smtp: el host %q apunta a una dirección no pública (%s); no permitido", h, ip)
		}
	}
	return nil
}
