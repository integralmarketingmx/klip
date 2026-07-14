#!/bin/sh
# Purga coherente de capturas Klip > 3 días.
# La imagen base (<slug>.png/.jpg/.jpeg/.gif) es la fuente de verdad del mtime; cuando expira,
# se borran JUNTOS sus archivos derivados (<slug>-og.png, <slug>.json, <slug>.txt) para no
# dejar huérfanos ni borrar derivados de slugs que aún viven.
#
# RETENCIÓN POR HILO ABIERTO (INBOX por MX, Sprint 4): si existe <slug>.replies.json,
# el slug tiene respuestas/hilo abierto y NO se purga (ni la imagen ni sus derivados),
# para no perder el contexto de la conversación. El sidecar de replies y sus imágenes
# (<slug>.reply-*.png/.jpg/...) se conservan mientras viva el hilo.
set -eu
DIR="${KLIP_UPLOAD_DIR:-/var/klip/uploads}"
[ -d "$DIR" ] || exit 0

# Lista de imágenes base expiradas (excluye las preview -og.png, que son derivados).
find "$DIR" -maxdepth 1 -type f -mtime +3 \
  \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.gif' \) \
  ! -name '*-og.png' ! -name '*.reply-*' -print | while IFS= read -r img; do
  base="$(basename "$img")"
  slug="${base%.*}"
  # Hilo abierto: si hay respuestas (<slug>.replies.json), NO se purga.
  if [ -f "$DIR/$slug.replies.json" ]; then
    continue
  fi
  # Borra la imagen y todos sus derivados del mismo slug.
  rm -f -- "$img" \
    "$DIR/$slug-og.png" \
    "$DIR/$slug.json" \
    "$DIR/$slug.txt"
done

# Barrido de seguridad: derivados huérfanos (sin imagen base) con > 3 días.
# Excluye los sidecars de respuestas (*.replies.json): son fuente de retención, no derivados.
find "$DIR" -maxdepth 1 -type f -mtime +3 \
  \( -name '*-og.png' -o -name '*.json' -o -name '*.txt' \) \
  ! -name '*.replies.json' -print | while IFS= read -r f; do
  base="$(basename "$f")"
  case "$base" in
    *-og.png) slug="${base%-og.png}" ;;
    *)        slug="${base%.*}" ;;
  esac
  # Si el slug tiene hilo abierto, conservamos sus derivados.
  if [ -f "$DIR/$slug.replies.json" ]; then
    continue
  fi
  # Si no existe ninguna imagen base del slug, es huérfano: bórralo.
  if ! ls "$DIR/$slug".png "$DIR/$slug".jpg "$DIR/$slug".jpeg "$DIR/$slug".gif >/dev/null 2>&1; then
    rm -f -- "$f"
  fi
done
