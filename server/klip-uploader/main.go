// klip-uploader: endpoint mínimo estilo Lightshot.
// Recibe una imagen por multipart (campo "file"), la guarda con un slug corto
// y devuelve un JSON con la URL pública. La auto-purga a 3 días la hace un
// systemd timer / cron aparte (find -mtime +3 -delete).
package main

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

const (
	uploadDir = "/var/klip/uploads"
	maxBytes  = 25 << 20 // 25 MB
	slugLen   = 6
	alphabet  = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789" // sin 0/O/1/l/I
)

// baseURL es el prefijo público de los links. Configurable por env KLIP_BASE_URL.
var baseURL = envOr("KLIP_BASE_URL", "https://klip.integralmarketing.agency")

func main() {
	if err := os.MkdirAll(uploadDir, 0o755); err != nil {
		log.Fatalf("no se pudo crear %s: %v", uploadDir, err)
	}
	addr := envOr("KLIP_ADDR", "127.0.0.1:8080")
	http.HandleFunc("/upload", handleUpload)
	http.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) { fmt.Fprint(w, "ok") })
	// Sirve las imágenes subidas como estático (GET /slug.png). Las rutas /upload y /health
	// son más específicas en el ServeMux, así que tienen prioridad sobre este "/".
	fs := http.FileServer(http.Dir(uploadDir))
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		if r.URL.Path == "/" { // raíz: nada que listar
			http.Error(w, "klip uploader", http.StatusOK)
			return
		}
		w.Header().Set("Cache-Control", "public, max-age=259200") // 3 días (expiran por purga)
		fs.ServeHTTP(w, r)
	})
	log.Printf("klip-uploader escuchando en %s, sirviendo %s", addr, baseURL)
	log.Fatal(http.ListenAndServe(addr, nil))
}

func handleUpload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
	file, hdr, err := r.FormFile("file")
	if err != nil {
		http.Error(w, "falta el campo 'file'", http.StatusBadRequest)
		return
	}
	defer file.Close()

	ext := strings.ToLower(filepath.Ext(hdr.Filename))
	if ext == "" || len(ext) > 5 {
		ext = ".png"
	}
	name := randSlug(slugLen) + ext
	dst, err := os.Create(filepath.Join(uploadDir, name))
	if err != nil {
		http.Error(w, "no se pudo guardar", http.StatusInternalServerError)
		return
	}
	defer dst.Close()
	if _, err := io.Copy(dst, file); err != nil {
		http.Error(w, "error al escribir", http.StatusInternalServerError)
		return
	}

	url := strings.TrimRight(baseURL, "/") + "/" + name
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"url": url})
	log.Printf("subido %s (%d bytes) -> %s", name, hdr.Size, url)
}

func randSlug(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "klipxx"
	}
	for i := range b {
		b[i] = alphabet[int(b[i])%len(alphabet)]
	}
	return string(b)
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
