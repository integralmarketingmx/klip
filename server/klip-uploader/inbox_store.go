// inbox_store.go: persistencia de las respuestas recibidas por MX propio (Sprint 4).
//
// Cada respuesta correlacionada a un slug se guarda como un sidecar JSON
// `<slug>.replies.json` en el uploadDir, en modo append (lista de respuestas).
// Esto permite que el endpoint /inbox una las respuestas leídas por Gmail (DWD)
// con las recibidas directamente por nuestro MX, deduplicadas por Message-ID.
//
// RETENCIÓN: mientras exista `<slug>.replies.json`, el slug tiene un hilo abierto
// y NO debe purgarse. El script deploy/klip-purge.sh respeta este archivo (ver
// el comentario allí). Los adjuntos de imagen se guardan como
// `<slug>.reply-<n>.<ext>` junto al sidecar.
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sync"
)

// mxReply es una respuesta entrante recibida por el MX propio y persistida.
// Se serializa al sidecar <slug>.replies.json. La estructura es un superconjunto
// compatible con Reply (inbound.go) para poder fusionarlas en /inbox.
type mxReply struct {
	Slug     string   `json:"slug"`
	From     string   `json:"from"`
	Subject  string   `json:"subject"`
	Snippet  string   `json:"snippet"`
	Date     string   `json:"date"`     // header Date crudo
	HasImage bool     `json:"hasImage"` // true si trae adjuntos de imagen
	Source   string   `json:"source"`   // siempre "mx" para las recibidas por nuestro MX
	MsgID    string   `json:"msgId"`    // Message-ID del correo entrante (para dedupe)
	Images   []string `json:"images,omitempty"` // nombres de archivo de imágenes guardadas
}

// inboxMu serializa lecturas/escrituras concurrentes del sidecar de replies.
// El SMTP puede recibir varios mensajes a la vez; protegemos el append.
var inboxMu sync.Mutex

// repliesPath devuelve la ruta del sidecar de respuestas de un slug.
func repliesPath(slug string) string {
	return filepath.Join(uploadDir, sanitizeSlug(slug)+".replies.json")
}

// readReplies lee las respuestas MX persistidas de un slug. Devuelve (nil, nil) si el archivo no
// existe, y (nil, err) si existe pero está ilegible/corrupto. DISTINGUIR esto es crítico: tratar un
// archivo corrupto como "vacío" haría que appendReply lo sobrescribiera, destruyendo respuestas.
func readReplies(slug string) ([]mxReply, error) {
	b, err := os.ReadFile(repliesPath(slug))
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	var out []mxReply
	if err := json.Unmarshal(b, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// backupCorruptReplies preserva un sidecar de respuestas corrupto (renombrándolo con un sufijo
// único) en vez de dejar que se sobrescriba. No destruye datos potencialmente recuperables.
func backupCorruptReplies(path string) {
	for i := 0; ; i++ {
		bak := fmt.Sprintf("%s.corrupt-%d", path, i)
		if _, err := os.Stat(bak); os.IsNotExist(err) {
			if err := os.Rename(path, bak); err != nil {
				log.Printf("ERROR: no se pudo respaldar replies corrupto %s: %v", path, err)
			} else {
				log.Printf("ADVERTENCIA: %s estaba corrupto; respaldado como %s", path, bak)
			}
			return
		}
	}
}

// appendReply agrega una respuesta al sidecar <slug>.replies.json en modo append.
// Deduplica por MsgID: si ya existe una respuesta con ese Message-ID, no la duplica.
// Es seguro para uso concurrente.
func appendReply(r mxReply) error {
	inboxMu.Lock()
	defer inboxMu.Unlock()

	slug := sanitizeSlug(r.Slug)
	r.Slug = slug
	if r.Source == "" {
		r.Source = "mx"
	}

	existing, err := readReplies(slug)
	if err != nil {
		// Corrupto/ilegible: respáldalo y arranca de cero, así no destruimos lo previo (queda en
		// el backup para recuperación) ni perdemos esta respuesta nueva.
		backupCorruptReplies(repliesPath(slug))
		existing = nil
	}
	// Dedupe por MsgID (si viene vacío, no deduplica y siempre agrega).
	if r.MsgID != "" {
		for _, e := range existing {
			if e.MsgID == r.MsgID {
				return nil // ya estaba; nada que hacer
			}
		}
	}
	existing = append(existing, r)

	b, err := json.MarshalIndent(existing, "", "  ")
	if err != nil {
		return err
	}
	return atomicWriteFile(repliesPath(slug), b, 0o644)
}

// mergeReplies fusiona las respuestas leídas por Gmail (DWD) con las recibidas
// por nuestro MX propio, deduplicadas por MsgID. Devuelve []Reply para mantener
// la forma JSON del endpoint /inbox. Las de Gmail tienen prioridad ante un mismo
// MsgID; el resto de MX se agregan a continuación.
func mergeReplies(gmail []Reply, mx []mxReply) []Reply {
	out := make([]Reply, 0, len(gmail)+len(mx))
	seen := make(map[string]bool, len(gmail)+len(mx))

	for _, r := range gmail {
		out = append(out, r)
		if r.MsgID != "" {
			seen[r.MsgID] = true
		}
	}
	for _, m := range mx {
		if m.MsgID != "" && seen[m.MsgID] {
			continue // ya estaba (probablemente vino por Gmail también)
		}
		if m.MsgID != "" {
			seen[m.MsgID] = true
		}
		out = append(out, Reply{
			Slug:     m.Slug,
			From:     m.From,
			Snippet:  m.Snippet,
			Date:     m.Date,
			HasImage: m.HasImage,
			MsgID:    m.MsgID,
			Source:   "mx",
		})
	}
	return out
}

// createUploadFile crea un archivo en el uploadDir de forma segura (sin path
// traversal: solo el nombre base). Lo usa el SMTP para guardar imágenes adjuntas.
func createUploadFile(name string) (*os.File, error) {
	return os.Create(filepath.Join(uploadDir, filepath.Base(name)))
}

// readAllMXReplies recorre el uploadDir y devuelve TODAS las respuestas MX
// persistidas (de todos los slugs). Lo usa /inbox para fusionar con Gmail.
func readAllMXReplies() []mxReply {
	entries, err := os.ReadDir(uploadDir)
	if err != nil {
		return nil
	}
	var out []mxReply
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		const suffix = ".replies.json"
		if len(name) <= len(suffix) || name[len(name)-len(suffix):] != suffix {
			continue
		}
		slug := name[:len(name)-len(suffix)]
		reps, _ := readReplies(slug) // vía de solo lectura: si está corrupto, omite (no destruye)
		out = append(out, reps...)
	}
	return out
}
