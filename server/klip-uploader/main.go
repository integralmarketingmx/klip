// klip-uploader: endpoint mínimo estilo Lightshot + visor web vestido.
// Recibe una imagen por multipart (campo "file"), la guarda con un slug corto
// y devuelve un JSON con la URL pública. Además genera un sidecar <slug>.json con
// metadatos y una preview OG 1200×630 (<slug>-og.png) para unfurls de Slack/WhatsApp.
// La página vestida (GET /<slug>) se renderiza en page.go.
// La auto-purga la hace un systemd timer / cron aparte (ver deploy/).
package main

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"image"
	_ "image/gif"  // registra decoders para DecodeConfig/Decode
	_ "image/jpeg" // idem
	"image/png"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	xdraw "golang.org/x/image/draw"
)

const (
	maxBytes = 25 << 20 // 25 MB
	slugLen   = 6
	alphabet  = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789" // sin 0/O/1/l/I

	retentionHours = 72 // los links viven 3 días (72h)
	ogW            = 1200
	ogH            = 630
	ogMaxBytes     = 300 << 10 // objetivo: preview OG < 300 KB
)

// baseURL es el prefijo público de los links. Configurable por env KLIP_BASE_URL.
var baseURL = envOr("KLIP_BASE_URL", "https://klip.integralmarketing.agency")

// uploadDir es el directorio de capturas. Configurable por env KLIP_UPLOAD_DIR (útil en tests).
var uploadDir = envOr("KLIP_UPLOAD_DIR", "/var/klip/uploads")

// meta es el contenido del sidecar <slug>.json.
type meta struct {
	W         int    `json:"w"`
	H         int    `json:"h"`
	Bytes     int64  `json:"bytes"`
	Created   int64  `json:"created"`   // unix segundos
	ExpiresAt int64  `json:"expiresAt"` // created + 72h
	OCR       string `json:"ocr"`
	Kind      string `json:"kind"` // "image"
	Views     int64  `json:"views"`
}

// viewCounters acumula vistas en memoria por slug; se vuelcan al sidecar.
var (
	viewMu       sync.Mutex
	viewCounters = map[string]*int64{}
)

func main() {
	if err := os.MkdirAll(uploadDir, 0o755); err != nil {
		log.Fatalf("no se pudo crear %s: %v", uploadDir, err)
	}
	addr := envOr("KLIP_ADDR", "127.0.0.1:8080")
	http.HandleFunc("/upload", handleUpload)
	http.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) { fmt.Fprint(w, "ok") })
	http.HandleFunc("/assets/logo.png", handleLogo)
	// Rutas más específicas (/upload, /health, /assets/…) tienen prioridad sobre "/".
	http.HandleFunc("/", handleRoot)
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
	slug := randSlug(slugLen)
	name := slug + ext
	dstPath := filepath.Join(uploadDir, name)
	dst, err := os.Create(dstPath)
	if err != nil {
		http.Error(w, "no se pudo guardar", http.StatusInternalServerError)
		return
	}
	written, err := io.Copy(dst, file)
	dst.Close()
	if err != nil {
		http.Error(w, "error al escribir", http.StatusInternalServerError)
		return
	}

	// La respuesta al cliente NO cambia: {"url": "…/slug.png"}. Lo sidecar/preview es best-effort.
	url := strings.TrimRight(baseURL, "/") + "/" + name
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"url": url})
	log.Printf("subido %s (%d bytes) -> %s", name, written, url)

	// Texto OCR opcional del campo multipart.
	ocr := strings.TrimSpace(r.FormValue("ocr"))

	// Decodifica dimensiones y genera sidecar + preview OG. Si algo falla, se loguea pero
	// no rompe la subida (el binario crudo ya quedó servible).
	created := time.Now().Unix()
	wpx, hpx := 0, 0
	if f, e := os.Open(dstPath); e == nil {
		if cfg, _, e2 := image.DecodeConfig(f); e2 == nil {
			wpx, hpx = cfg.Width, cfg.Height
		}
		f.Close()
	}
	m := meta{
		W: wpx, H: hpx, Bytes: written,
		Created: created, ExpiresAt: created + retentionHours*3600,
		OCR: ocr, Kind: "image", Views: 0,
	}
	if e := writeMeta(slug, m); e != nil {
		log.Printf("aviso: no se pudo escribir sidecar %s.json: %v", slug, e)
	}
	if e := makeOGPreview(dstPath, slug); e != nil {
		log.Printf("aviso: no se pudo generar preview OG de %s: %v", slug, e)
	}
}

// writeMeta serializa el sidecar <slug>.json.
func writeMeta(slug string, m meta) error {
	b, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(uploadDir, slug+".json"), b, 0o644)
}

// readMeta lee el sidecar <slug>.json si existe.
func readMeta(slug string) (meta, bool) {
	var m meta
	b, err := os.ReadFile(filepath.Join(uploadDir, slug+".json"))
	if err != nil {
		return m, false
	}
	if json.Unmarshal(b, &m) != nil {
		return m, false
	}
	return m, true
}

// makeOGPreview redimensiona la captura sobre un lienzo 1200×630 (fondo neutro, "contain")
// y la guarda como <slug>-og.png. Si el PNG supera ~300 KB, recae a JPEG comprimido con la
// misma extensión .png (Slack/WhatsApp leen por bytes, no por extensión) para mantener el peso.
func makeOGPreview(srcPath, slug string) error {
	f, err := os.Open(srcPath)
	if err != nil {
		return err
	}
	defer f.Close()
	src, _, err := image.Decode(f)
	if err != nil {
		return err
	}

	// Lienzo neutro 1200×630.
	canvas := image.NewRGBA(image.Rect(0, 0, ogW, ogH))
	neutral := image.NewUniform(neutralBG())
	xdraw.Draw(canvas, canvas.Bounds(), neutral, image.Point{}, xdraw.Src)

	// "contain": escala manteniendo el aspecto, centrado, sin recortar.
	sb := src.Bounds()
	sw, sh := sb.Dx(), sb.Dy()
	if sw <= 0 || sh <= 0 {
		return fmt.Errorf("dimensiones inválidas")
	}
	scale := minF(float64(ogW)/float64(sw), float64(ogH)/float64(sh))
	if scale > 1 {
		scale = 1 // no agrandar capturas chicas; se centran sobre el lienzo
	}
	dw, dh := int(float64(sw)*scale), int(float64(sh)*scale)
	if dw < 1 {
		dw = 1
	}
	if dh < 1 {
		dh = 1
	}
	ox, oy := (ogW-dw)/2, (ogH-dh)/2
	dstRect := image.Rect(ox, oy, ox+dw, oy+dh)
	xdraw.CatmullRom.Scale(canvas, dstRect, src, sb, xdraw.Over, nil)

	outPath := filepath.Join(uploadDir, slug+"-og.png")
	out, err := os.Create(outPath)
	if err != nil {
		return err
	}
	defer out.Close()

	// Intento 1: PNG. Si pesa demasiado, recae a JPEG comprimido (mismo archivo .png).
	enc := png.Encoder{CompressionLevel: png.BestCompression}
	if err := enc.Encode(out, canvas); err != nil {
		return err
	}
	if fi, e := out.Stat(); e == nil && fi.Size() > ogMaxBytes {
		// Re-encode como JPEG calidad descendente hasta caber.
		if e := reencodeJPEGUnder(outPath, canvas, ogMaxBytes); e != nil {
			log.Printf("aviso: preview OG quedó >300KB (%d) y falló JPEG: %v", fi.Size(), e)
		}
	}
	return nil
}

// handleLogo sirve el logo embebido en /assets/logo.png.
func handleLogo(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "image/png")
	w.Header().Set("Cache-Control", "public, max-age=604800")
	_, _ = w.Write(logoPNG)
}

// handleRoot decide: binario .png / -og.png, o página vestida / 404 vestido.
func handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	p := strings.TrimPrefix(r.URL.Path, "/")
	if p == "" { // raíz
		http.Error(w, "klip uploader", http.StatusOK)
		return
	}
	// Binarios: se sirven crudos (incluye <slug>-og.png).
	if strings.HasSuffix(p, ".png") || strings.HasSuffix(p, ".jpg") || strings.HasSuffix(p, ".jpeg") || strings.HasSuffix(p, ".gif") {
		serveBinary(w, r, p)
		return
	}
	// Cualquier otra ruta sin extensión de imagen: página vestida del slug.
	slug := p
	if i := strings.IndexByte(slug, '/'); i >= 0 {
		slug = slug[:i]
	}
	servePage(w, r, slug)
}

// serveBinary entrega un archivo subido crudo con cache de 3 días.
func serveBinary(w http.ResponseWriter, r *http.Request, name string) {
	// Evita path traversal: solo el nombre base.
	name = filepath.Base(name)
	full := filepath.Join(uploadDir, name)
	if _, err := os.Stat(full); err != nil {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Cache-Control", "public, max-age=259200")
	http.ServeFile(w, r, full)
}

// countView incrementa la vista en memoria (excluye crawlers) y vuelca al sidecar.
func countView(slug string, ua string) {
	if isCrawler(ua) {
		return
	}
	viewMu.Lock()
	c, ok := viewCounters[slug]
	if !ok {
		var z int64
		// Arranca desde el valor ya persistido.
		if m, found := readMeta(slug); found {
			z = m.Views
		}
		c = &z
		viewCounters[slug] = c
	}
	viewMu.Unlock()
	n := atomic.AddInt64(c, 1)
	// Flush al sidecar (best-effort).
	if m, found := readMeta(slug); found {
		m.Views = n
		_ = writeMeta(slug, m)
	}
}

// isCrawler detecta bots de unfurl por User-Agent para no inflar el contador.
func isCrawler(ua string) bool {
	ua = strings.ToLower(ua)
	for _, bot := range []string{
		"slackbot", "facebookexternalhit", "twitterbot", "discordbot",
		"whatsapp", "linkedinbot", "telegrambot", "bot", "spider", "crawler", "preview",
	} {
		if strings.Contains(ua, bot) {
			return true
		}
	}
	return false
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

func minF(a, b float64) float64 {
	if a < b {
		return a
	}
	return b
}
