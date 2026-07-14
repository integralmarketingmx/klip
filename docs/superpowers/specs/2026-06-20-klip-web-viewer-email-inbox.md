# Klip — Visor web del link, Email (OAuth) e Inbox · Plan maestro

**Fecha:** 2026-06-20 · **Rama:** Mike-Martin · **Estado:** spec aprobado (build Sprint 1 en curso)

Consolidación de TODAS las features pedidas, validada por research + discusión + planning multi-agente
(workflow `klip-master-plan`, 13 agentes). Co-proyecto con Martin Velasco (ver memoria `colaboracion-con-martin`).

## Secuencia de releases

- **Sprint 0 (paralelo, gestión):** OAuth Google `gmail.send` + Developer ID. *Lead-time externo.*
- **Sprint 1 (ya, sin Martin):** visor web vestido en `/slug` (HTML, metadatos, OG cards, OCR copiable, badge expiración, 404, i18n, contador, purga coherente).
- **Sprint 2 (ya, sin Martin):** visor de nota de voz (player + transcripción) + anotador web (fabric.js).
- **Sprint 3 (OAuth listo):** email desde el Gmail del usuario + compositor To/CC/CCO/notas + SMTP fallback + marcadores de correlación.
- **Sprint 4 (MX/dominio):** inbox (ingestión, correlación 3 capas, retención por hilo, Klip-a-Klip).

## Construir YA (sin Martin) — Sprint 1, orden de ejecución

Crítico: #1 sidecar → #2 HTML → #5 preview OG.

1. **Sidecar `slug.json` + recibir OCR por multipart.** `main.go handleUpload`; `UploaderClient.swift` (+`ocrText`); `PanelController+Upload` pasa `item.text`. *Acept.:* subir con OCR crea `<slug>.json` con w/h/bytes/created/ocr; `/upload` sigue devolviendo `{url}` idéntico (regresión cero).
2. **Branch handler `/` → HTML vestido.** `strings.HasSuffix(".png")`; `page.go` con `//go:embed`; `html/template` (auto-escape). *Acept.:* `GET /<slug>` HTML; `/<slug>.png` binario; OCR con `<script>` aparece escapado.
3. **Bloque OCR copiable** debajo de la imagen + "Copiar texto".
4. **OG/Twitter cards primero en `<head>`** (Slackbot lee 32KB), og:image URL https absoluta.
5. **Preview 1200×630 <300KB re-encode en Go** → `/slug-og.png`; og:image apunta ahí. *La única no-trivial; obligatoria por WhatsApp (ratio ≤4:1, <600KB).*
6. **Estado 404/expirado vestido** (no el plano del FileServer).
7. **i18n ES/EN** (`?lang=` + Accept-Language).
8. **Contador ligero + filtro de crawlers** (`atomic.AddInt64` + flush sidecar; blocklist Slackbot/facebookexternalhit/Twitterbot/Discordbot/WhatsApp).
9. **Purga extendida coherente** (PNG + json + -og.png + .txt juntos; sin huérfanos).

Fast-follow S2 sin Martin: voz web (player + transcripción, Accept-Ranges) y anotador fabric.js (blur **crop→filtro→overlay**, export retina-safe, re-subir).

## Bloqueado por Martin

- **OAuth Google `gmail.send` (ÚNICO scope).** Sensible, **NO dispara CASA**. **App creada Internal en Workspace `integralmarketing.agency`** (proyecto `klip-integralmarketing-agency`) → sin verificación, sin caducidad de token de 7d, solo cuentas del dominio. Para usuarios externos: External + verificación (decisión futura con Martin). NUNCA pedir scopes de lectura de Gmail (`readonly/modify/metadata` = restringidos → CASA, miles de USD).
- **Developer ID + notarización ($99/año)** → Keychain real + DMG sin Gatekeeper.
- **MX + buzón/parser en VPS** para dominio de marca `klip+<slug>@…` → única ingestión de inbox sin CASA.
- Negocio: retención >3d, cuentas/board persistente, SMTP propio.

## Riesgos top

1. WhatsApp rompe unfurl si og:image = PNG crudo → preview 1200×630 <300KB (#5).
2. Retención 3d vs email (link muere antes de abrirse) → decidir `expiresAt`/`hasThread` en S1; recursos con hilo vivo no se purgan.
3. XSS por OCR/metadatos → SOLO `html/template`; prohibido `text/template`/`template.HTML()` sobre texto del usuario.
4. Detección de respuesta entrante → señal primaria `In-Reply-To`/`References` + `Message-ID` determinista; fallback token `[klip#slug]` en asunto. `X-Klip-Thread` solo primer salto.
5. Auto-conteo por crawlers → blocklist User-Agents.
6. Blur de región → crop→filtro→overlay (no filtro global); re-rasterizar al export.
7. Enviar vía Gmail API (DKIM de Google intacto, no tocar From; Reply-To en dominio Klip).

## Archivos clave

`server/klip-uploader/{main.go,page.go,page.html,correlate.go(S3),inbound.go(S4)}`;
`Sources/Klip/{UploaderClient.swift,PanelController+Upload.swift,GmailOAuthClient.swift(S3),ThreadStore.swift(S3-4)}`.
