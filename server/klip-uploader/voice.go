// voice.go: soporte de notas de voz (kind == "voice") en el visor web.
// La lógica nueva vive aquí para minimizar conflictos en main.go.
// El binario de audio se sirve igual que las imágenes en /<slug>.<ext> con
// Accept-Ranges (http.ServeFile ya soporta Range/seek del <audio>).
package main

import (
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// servePageVoice renderiza la variante audio del visor (kind == "voice").
// Reutiliza la misma plantilla page.html (rama {{if .IsVoice}}).
func servePageVoice(w http.ResponseWriter, r *http.Request, slug string, d dict, base string, m meta) {
	ext := m.Ext
	if ext == "" {
		ext = ".m4a"
	}
	audioName := slug + ext

	created := time.Now()
	if m.Created > 0 {
		created = time.Unix(m.Created, 0)
	}
	expires := created.Add(retentionHours * time.Hour)

	transcript := strings.TrimSpace(m.Transcript)
	durHuman := humanDuration(m.Duration)

	pd := pageData{
		D:             d,
		Slug:          slug,
		IsVoice:       true,
		AudioURL:      base + "/" + audioName,
		AudioExt:      strings.TrimPrefix(ext, "."),
		DurationHuman: durHuman,
		HasTranscript: transcript != "",
		Transcript:    transcript,
		SizeHuman:     humanBytes(m.Bytes),
		UploadedAgo:   fmt.Sprintf(d.UploadedAgo, humanDur(time.Since(created))),
		ExpiresIn:     fmt.Sprintf(d.ExpiresIn, humanDur(time.Until(expires))),
		ExpireBadge:   fmt.Sprintf(d.ExpiresInBadge, humanDur(time.Until(expires))),
		Views:         m.Views,
		PageURL:       base + "/" + slug,
		LogoURL:       base + "/assets/logo.png",
	}

	// OG: "Nota de voz · 0:42 — Klip" + inicio de la transcripción.
	pd.OGTitle = d.VoiceTitle + " · " + durHuman + " — Klip"
	pd.OGDesc = "Nota de voz compartida con Klip"
	if pd.HasTranscript {
		pd.OGDesc = truncate(transcript, 180)
	}

	if r.Method == http.MethodGet {
		countView(slug, r.Header.Get("User-Agent"))
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := tmpl.Execute(w, pd); err != nil {
		http.Error(w, "render error", http.StatusInternalServerError)
	}
}

// audioExts son las extensiones de audio aceptadas para notas de voz.
var audioExts = map[string]bool{
	".m4a": true,
	".mp3": true,
	".ogg": true,
	".wav": true,
}

// isAudioExt indica si ext (ya en minúsculas, con punto) es una extensión de audio soportada.
func isAudioExt(ext string) bool {
	return audioExts[ext]
}

// writeVoiceMeta escribe el sidecar <slug>.json de una nota de voz a partir de los
// campos multipart (transcript, duration). Best-effort: si falla solo loguea.
func writeVoiceMeta(slug, ext string, written int64, r *http.Request) {
	transcript := strings.TrimSpace(r.FormValue("transcript"))
	duration := 0
	if d := strings.TrimSpace(r.FormValue("duration")); d != "" {
		if n, err := strconv.Atoi(d); err == nil && n >= 0 {
			duration = n
		}
	}
	created := time.Now().Unix()
	m := meta{
		Bytes:      written,
		Created:    created,
		ExpiresAt:  created + retentionHours*3600,
		Kind:       "voice",
		Ext:        ext,
		Transcript: transcript,
		Duration:   duration,
		Views:      0,
	}
	if e := writeMeta(slug, m); e != nil {
		log.Printf("aviso: no se pudo escribir sidecar de voz %s.json: %v", slug, e)
	}
}

// humanDuration formatea segundos a "m:ss" (p.ej. 42 -> "0:42", 95 -> "1:35").
func humanDuration(secs int) string {
	if secs < 0 {
		secs = 0
	}
	m := secs / 60
	s := secs % 60
	return strconv.Itoa(m) + ":" + zeroPad(s)
}

// zeroPad antepone un 0 a los segundos < 10.
func zeroPad(n int) string {
	if n < 10 {
		return "0" + strconv.Itoa(n)
	}
	return strconv.Itoa(n)
}
