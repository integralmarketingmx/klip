// page.go: render de la página vestida del visor (GET /<slug>) y del 404 vestido.
// Usa html/template (auto-escape OBLIGATORIO) para blindar OCR/metadatos contra XSS.
package main

import (
	_ "embed"
	"fmt"
	"html/template"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

//go:embed page.html
var pageHTMLRaw string

//go:embed logo.png
var logoPNG []byte

// tmpl es la plantilla compilada una sola vez. html/template auto-escapa todo lo que venga
// del usuario (OCR, dimensiones, slug) en contexto HTML/atributo/JS.
var tmpl = template.Must(template.New("page").Parse(pageHTMLRaw))

// strings de i18n (ES por defecto, EN opcional). Nada hardcodeado fuera de este dict.
type dict struct {
	Lang               string
	DownloadMac        string
	CopyLink           string
	Download           string
	CopyImage          string
	OCRTitle           string
	CopyText           string
	MadeWith           string
	Privacy            string
	AutoDeletes        string
	UploadedAgo        string // "subido hace %s" / "uploaded %s ago"
	ExpiresIn          string // "se borra en %s" / "deletes in %s"
	ExpiresInBadge     string
	Views              string
	NotFoundTitle      string
	NotFoundBody       string
	NotFoundCTA        string
	LinkCopied         string
	ImageCopied        string
	TextCopied         string
	CopyImgUnsupported string
	// Anotador web (Sprint 2)
	Annotate      string // botón "✏️ Anotar"
	EditorTitle   string
	ToolArrow     string
	ToolRect      string
	ToolEllipse   string
	ToolLine      string
	ToolText      string
	ToolHighlight string
	ToolNumber    string
	ToolBlur      string
	Undo          string
	Clear         string
	UploadBack    string // "Subir de vuelta"
	Uploading     string
	NewLinkReady  string
	UploadFailed  string
	// Nota de voz (Sprint 2)
	VoiceTitle       string // "Nota de voz"
	TranscriptTitle  string // "Transcripción"
	CopyTranscript   string
	DownloadAudio    string
	TranscriptCopied string
	NoTranscript     string
}

var dicts = map[string]dict{
	"es": {
		Lang: "es", DownloadMac: "Descargar Klip para Mac",
		CopyLink: "Copiar link", Download: "Descargar", CopyImage: "Copiar imagen",
		OCRTitle: "Texto detectado (OCR)", CopyText: "Copiar texto",
		MadeWith: "Hecho con", Privacy: "Privacidad", AutoDeletes: "Se autoelimina en 3 días",
		UploadedAgo: "subido hace %s", ExpiresIn: "se borra en %s", ExpiresInBadge: "Se borra en %s",
		Views:         "%d vistas",
		NotFoundTitle: "Esta captura ya no está", NotFoundBody: "El link expiró o nunca existió. Los links de Klip se autoeliminan a los 3 días.",
		NotFoundCTA: "Crear la tuya con Klip",
		LinkCopied:  "Link copiado", ImageCopied: "Imagen copiada", TextCopied: "Texto copiado",
		CopyImgUnsupported: "Tu navegador no permite copiar imágenes",
		Annotate:           "Anotar", EditorTitle: "Anotar captura",
		ToolArrow: "Flecha", ToolRect: "Rectángulo", ToolEllipse: "Elipse", ToolLine: "Línea",
		ToolText: "Texto", ToolHighlight: "Resaltador", ToolNumber: "Número", ToolBlur: "Difuminar",
		Undo: "Deshacer", Clear: "Limpiar", UploadBack: "Subir de vuelta", Uploading: "Subiendo…",
		NewLinkReady: "Nuevo link listo y copiado", UploadFailed: "No se pudo subir",
		VoiceTitle: "Nota de voz", TranscriptTitle: "Transcripción", CopyTranscript: "Copiar transcripción",
		DownloadAudio: "Descargar audio", TranscriptCopied: "Transcripción copiada",
		NoTranscript: "Sin transcripción",
	},
	"en": {
		Lang: "en", DownloadMac: "Download Klip for Mac",
		CopyLink: "Copy link", Download: "Download", CopyImage: "Copy image",
		OCRTitle: "Detected text (OCR)", CopyText: "Copy text",
		MadeWith: "Made with", Privacy: "Privacy", AutoDeletes: "Auto-deletes in 3 days",
		UploadedAgo: "uploaded %s ago", ExpiresIn: "deletes in %s", ExpiresInBadge: "Deletes in %s",
		Views:         "%d views",
		NotFoundTitle: "This screenshot is gone", NotFoundBody: "The link expired or never existed. Klip links auto-delete after 3 days.",
		NotFoundCTA: "Make yours with Klip",
		LinkCopied:  "Link copied", ImageCopied: "Image copied", TextCopied: "Text copied",
		CopyImgUnsupported: "Your browser can't copy images",
		Annotate:           "Annotate", EditorTitle: "Annotate screenshot",
		ToolArrow: "Arrow", ToolRect: "Rectangle", ToolEllipse: "Ellipse", ToolLine: "Line",
		ToolText: "Text", ToolHighlight: "Highlighter", ToolNumber: "Number", ToolBlur: "Blur",
		Undo: "Undo", Clear: "Clear", UploadBack: "Upload back", Uploading: "Uploading…",
		NewLinkReady: "New link ready and copied", UploadFailed: "Upload failed",
		VoiceTitle: "Voice note", TranscriptTitle: "Transcript", CopyTranscript: "Copy transcript",
		DownloadAudio: "Download audio", TranscriptCopied: "Transcript copied",
		NoTranscript: "No transcript",
	},
}

// pickLang elige idioma: ?lang= fuerza; si no, Accept-Language; default es.
func pickLang(r *http.Request) dict {
	if q := strings.ToLower(r.URL.Query().Get("lang")); q != "" {
		if d, ok := dicts[q]; ok {
			return d
		}
	}
	al := strings.ToLower(r.Header.Get("Accept-Language"))
	if strings.HasPrefix(al, "en") || strings.Contains(al, ",en") {
		return dicts["en"]
	}
	return dicts["es"]
}

// pageData alimenta page.html. Solo tipos seguros (strings/ints) → html/template escapa todo.
type pageData struct {
	D dict

	Slug        string
	NotFound    bool
	HasOCR      bool
	OCR         string
	WxH         string
	Dimensions  string // alias humano
	Width       int
	Height      int
	SizeHuman   string
	UploadedAgo string
	ExpiresIn   string
	ExpireBadge string
	Views       int64

	// URLs absolutas (https) para OG/Twitter y para los botones/JS.
	PageURL  string
	ImageURL string
	OGImage  string
	LogoURL  string

	OGTitle string
	OGDesc  string

	// Nota de voz (kind == "voice").
	IsVoice       bool
	AudioURL      string
	AudioExt      string // "m4a", "mp3", … sin punto, para mostrar
	DurationHuman string // "0:42"
	HasTranscript bool
	Transcript    string
}

// servePage renderiza la página del slug o un 404 vestido si no existe.
func servePage(w http.ResponseWriter, r *http.Request, slug string) {
	d := pickLang(r)
	base := strings.TrimRight(baseURL, "/")

	// Lee el sidecar primero: una nota de voz no tiene binario de imagen.
	m, hasMeta := readMeta(slug)
	if hasMeta && m.Kind == "voice" {
		servePageVoice(w, r, slug, d, base, m)
		return
	}

	// Localiza el binario del slug (png/jpg/jpeg/gif).
	imgName, ok := findImage(slug)
	if !ok {
		// 404 vestido, misma plantilla.
		pd := pageData{D: d, Slug: slug, NotFound: true, LogoURL: base + "/assets/logo.png", PageURL: base + "/" + slug}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusNotFound)
		_ = tmpl.Execute(w, pd)
		return
	}

	created := time.Now()
	if hasMeta && m.Created > 0 {
		created = time.Unix(m.Created, 0)
	} else if fi, e := os.Stat(filepath.Join(uploadDir, imgName)); e == nil {
		created = fi.ModTime()
	}
	expires := created.Add(retentionHours * time.Hour)

	pd := pageData{
		D:           d,
		Slug:        slug,
		HasOCR:      strings.TrimSpace(m.OCR) != "",
		OCR:         m.OCR,
		Width:       m.W,
		Height:      m.H,
		WxH:         fmt.Sprintf("%d×%d", m.W, m.H),
		SizeHuman:   humanBytes(m.Bytes),
		UploadedAgo: fmt.Sprintf(d.UploadedAgo, humanDur(time.Since(created))),
		ExpiresIn:   fmt.Sprintf(d.ExpiresIn, humanDur(time.Until(expires))),
		ExpireBadge: fmt.Sprintf(d.ExpiresInBadge, humanDur(time.Until(expires))),
		Views:       m.Views,
		PageURL:     base + "/" + slug,
		ImageURL:    base + "/" + imgName,
		OGImage:     base + "/" + slug + "-og.png",
		LogoURL:     base + "/assets/logo.png",
	}
	if pd.Width <= 0 || pd.Height <= 0 {
		pd.WxH = ""
	}
	// OG title/desc: si hay OCR, úsalo recortado como descripción.
	pd.OGTitle = "Klip · " + pd.WxH
	if pd.WxH == "" {
		pd.OGTitle = "Klip"
	}
	pd.OGDesc = "Captura compartida con Klip"
	if pd.HasOCR {
		pd.OGDesc = truncate(strings.TrimSpace(m.OCR), 180)
	}

	// Cuenta la vista (excluye crawlers) solo en GET de la página HTML.
	if r.Method == http.MethodGet {
		countView(slug, r.Header.Get("User-Agent"))
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := tmpl.Execute(w, pd); err != nil {
		http.Error(w, "render error", http.StatusInternalServerError)
	}
}

// findImage busca el binario del slug probando extensiones comunes.
func findImage(slug string) (string, bool) {
	for _, ext := range []string{".png", ".jpg", ".jpeg", ".gif"} {
		name := slug + ext
		if _, err := os.Stat(filepath.Join(uploadDir, name)); err == nil {
			return name, true
		}
	}
	return "", false
}

// humanBytes formatea bytes a KB/MB legibles.
func humanBytes(b int64) string {
	switch {
	case b >= 1<<20:
		return fmt.Sprintf("%.1f MB", float64(b)/(1<<20))
	case b >= 1<<10:
		return fmt.Sprintf("%d KB", b/(1<<10))
	default:
		return fmt.Sprintf("%d B", b)
	}
}

// humanDur formatea una duración a "Xd Yh" / "Xh" / "Xm".
func humanDur(dd time.Duration) string {
	if dd < 0 {
		dd = 0
	}
	days := int(dd.Hours()) / 24
	hours := int(dd.Hours()) % 24
	mins := int(dd.Minutes()) % 60
	switch {
	case days > 0:
		return fmt.Sprintf("%dd %dh", days, hours)
	case hours > 0:
		return fmt.Sprintf("%dh", hours)
	default:
		return fmt.Sprintf("%dm", mins)
	}
}

func truncate(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return strings.TrimSpace(string(r[:n])) + "…"
}
