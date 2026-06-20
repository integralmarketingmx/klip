#!/bin/sh
# Purga coherente de capturas Klip > 3 días.
# La imagen base (<slug>.png/.jpg/.jpeg/.gif) es la fuente de verdad del mtime; cuando expira,
# se borran JUNTOS sus archivos derivados (<slug>-og.png, <slug>.json, <slug>.txt) para no
# dejar huérfanos ni borrar derivados de slugs que aún viven.
set -eu
DIR="${KLIP_UPLOAD_DIR:-/var/klip/uploads}"
[ -d "$DIR" ] || exit 0

# Lista de imágenes base expiradas (excluye las preview -og.png, que son derivados).
find "$DIR" -maxdepth 1 -type f -mtime +3 \
  \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.gif' \) \
  ! -name '*-og.png' -print | while IFS= read -r img; do
  base="$(basename "$img")"
  slug="${base%.*}"
  # Borra la imagen y todos sus derivados del mismo slug.
  rm -f -- "$img" \
    "$DIR/$slug-og.png" \
    "$DIR/$slug.json" \
    "$DIR/$slug.txt"
done

# Barrido de seguridad: derivados huérfanos (sin imagen base) con > 3 días.
find "$DIR" -maxdepth 1 -type f -mtime +3 \
  \( -name '*-og.png' -o -name '*.json' -o -name '*.txt' \) -print | while IFS= read -r f; do
  base="$(basename "$f")"
  case "$base" in
    *-og.png) slug="${base%-og.png}" ;;
    *)        slug="${base%.*}" ;;
  esac
  # Si no existe ninguna imagen base del slug, es huérfano: bórralo.
  if ! ls "$DIR/$slug".png "$DIR/$slug".jpg "$DIR/$slug".jpeg "$DIR/$slug".gif >/dev/null 2>&1; then
    rm -f -- "$f"
  fi
done
