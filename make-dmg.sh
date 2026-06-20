#!/bin/bash
# Empaqueta Klip.app en un .dmg instalable (arrastrar a Aplicaciones).
# Requiere haber corrido antes: ./build.sh release   (genera ./Klip.app)
set -euo pipefail

APP="Klip.app"
VOL="Klip"
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "0.4")
DMG="Klip-$VER.dmg"
STAGE="$(mktemp -d)/dmg"

[ -d "$APP" ] || { echo "No existe $APP. Corre ./build.sh release primero."; exit 1; }

echo "==> Preparando contenido del DMG…"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Aplicaciones"

# Instrucciones dentro del DMG (Gatekeeper: app autofirmada, no notarizada).
cat > "$STAGE/LÉEME - cómo instalar.txt" <<'TXT'
Klip — instalación

1) Arrastra "Klip.app" a la carpeta "Aplicaciones".

2) La PRIMERA vez, macOS dirá que no puede verificar al desarrollador
   (la app está autofirmada, no viene de la App Store). Para abrirla:
   - Ve a Aplicaciones, haz CLIC DERECHO sobre Klip → "Abrir".
   - En el aviso, pulsa "Abrir" de nuevo.
   (Solo hace falta la primera vez.)

   Si macOS no te da la opción "Abrir", ejecuta esto en la Terminal:
     xattr -dr com.apple.quarantine /Applications/Klip.app

3) Klip vive en la barra de menú (icono de portapapeles, arriba a la derecha).
   Atajos: ⌘⇧E historial · ⌘⇧I voz · ⌘⇧2 capturar y anotar.

4) Para transcribir voz necesitas una API key (OpenAI o Gemini):
   ábrela en Klip → Preferencias → pega tu clave.

Requiere macOS 14 (Sonoma) o posterior, Mac con Apple Silicon (M1 o más nuevo).
TXT

echo "==> Creando ${DMG} …"
rm -f "$DMG"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$(dirname "$STAGE")"

echo "✓ Listo: $DMG  ($(du -h "$DMG" | cut -f1))"
