// image.go: helpers de imagen para la preview OG (lienzo neutro y re-encode JPEG).
package main

import (
	"image"
	"image/color"
	"image/jpeg"
	"os"
)

// neutralBG es el color de fondo del lienzo OG (gris neutro claro).
func neutralBG() color.Color {
	return color.RGBA{R: 0x1d, G: 0x21, B: 0x29, A: 0xff} // mismo tono "card" oscuro del visor
}

// reencodeJPEGUnder re-escribe outPath como JPEG bajando la calidad hasta caber en maxBytes.
// Mantiene el nombre <slug>-og.png a propósito: Slack/WhatsApp detectan el tipo por bytes.
func reencodeJPEGUnder(outPath string, img image.Image, maxBytes int64) error {
	for _, q := range []int{85, 75, 65, 55, 45} {
		f, err := os.Create(outPath)
		if err != nil {
			return err
		}
		err = jpeg.Encode(f, img, &jpeg.Options{Quality: q})
		f.Close()
		if err != nil {
			return err
		}
		if fi, e := os.Stat(outPath); e == nil && fi.Size() <= maxBytes {
			return nil
		}
	}
	return nil // se queda con la última (q=45); mejor algo que nada
}
