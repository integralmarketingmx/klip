// edit.go: anotador web (Sprint 2). Sirve un editor fabric.js self-hosted en
// GET /<slug>/edit que carga la imagen del slug como fondo y un lienzo encima.
// El export se hace 100% en el navegador (toDataURL multiplier:2); el botón
// "Subir de vuelta" reusa POST /upload con el blob anotado.
// fabric.js va embebido (//go:embed), NADA de CDN.
package main

import (
	_ "embed"
	"html/template"
	"net/http"
	"strings"
)

//go:embed assets/fabric.min.js
var fabricJS []byte

//go:embed edit.html
var editHTMLRaw string

// editTmpl se compila una vez. html/template auto-escapa slug/URLs (XSS).
var editTmpl = template.Must(template.New("edit").Parse(editHTMLRaw))

// editData alimenta edit.html.
type editData struct {
	D         dict
	Slug      string
	ImageURL  string // imagen de fondo a anotar
	UploadURL string // endpoint para "Subir de vuelta"
	BaseURL   string // base pública (para construir el nuevo link)
	LogoURL   string
	FabricURL string
}

// handleFabric sirve fabric.js embebido con cache largo.
func handleFabric(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/javascript; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=604800")
	_, _ = w.Write(fabricJS)
}

// serveEdit renderiza el editor para un slug de imagen. Si el slug no existe o
// no es imagen (p.ej. una nota de voz), responde 404 vestido reutilizando servePage.
func serveEdit(w http.ResponseWriter, r *http.Request, slug string) {
	imgName, ok := findImage(slug)
	if !ok {
		// No hay imagen anotable → 404 vestido coherente con el resto.
		servePage(w, r, slug)
		return
	}
	base := strings.TrimRight(baseURL, "/")
	ed := editData{
		D:         pickLang(r),
		Slug:      slug,
		ImageURL:  base + "/" + imgName,
		UploadURL: base + "/upload",
		BaseURL:   base,
		LogoURL:   base + "/assets/logo.png",
		FabricURL: base + "/assets/fabric.min.js",
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := editTmpl.Execute(w, ed); err != nil {
		http.Error(w, "render error", http.StatusInternalServerError)
	}
}
