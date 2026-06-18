# Klip

## What This Is

Klip es un gestor de portapapeles nativo de macOS (Swift/AppKit + SwiftUI, SwiftPM sin Xcode, app de barra de menú) con historial de texto e imágenes, búsqueda instantánea, OCR (Vision), notas de voz transcritas (OpenAI/Gemini), Markdown y mini gestor de credenciales. Open source (MIT), local-first y sin telemetría.

## Core Value

Todo lo que copias queda capturado, persistente y buscable, a un atajo de distancia — sin que nada salga de tu Mac salvo lo que tú decides transcribir.

## Milestone Actual: v0.5 — "Captura nativa + control de transcripción"

Añadir captura de pantalla con anotación al estilo Lightshot que alimenta el historial persistente y buscable de Klip, más control del modelo de Gemini para la transcripción de voz. Objetivo de negocio: demo ante el dueño de Lightshot que muestre la integración como una evolución (captura + memoria + OCR), no como un clon.

## Requirements

### Validated

<!-- Shipped y confirmado en el código existente -->

- ✓ Historial de portapapeles texto + imágenes con persistencia local (`0600`) — v0.4
- ✓ Búsqueda con resaltado y navegación por teclado — v0.4
- ✓ OCR de imágenes vía Vision (local) — v0.4
- ✓ Notas de voz → texto (OpenAI o Gemini) con audio guardado y reintento — v0.4
- ✓ Atajos globales configurables (panel `⌘⇧E`, voz `⌘⇧I`) vía Carbon — v0.4
- ✓ Menú principal con menú Editar (⌘X/⌘C/⌘V/⌘A en campos de texto) — v0.4 (fix reciente)

### Active

<!-- Scope del milestone v0.5 -->

- [ ] Captura de región de pantalla con overlay "freeze-frame" y badge de dimensiones en vivo (`⌘⇧2`, configurable)
- [ ] Editor de anotaciones: lápiz, línea, flecha, rectángulo, elipse, marcador, texto, color, grosor, deshacer
- [ ] Copiar/Guardar la captura anotada → entra al historial persistente de Klip (con OCR y búsqueda)
- [ ] Gestión del permiso TCC de Grabación de pantalla (verificación + onboarding)
- [ ] Selector de modelo de Google Gemini en Preferencias (hoy fijo en `gemini-flash-latest`)

### Out of Scope

- Subir a URL pública (prntscr.com) / compartir en redes / buscar en Google Images / imprimir — fuera de la demo; requieren backend o IP de terceros (pendiente para más adelante)
- Reutilizar los assets `.tiff` de Lightshot — son IP de Skillbrains; se usan SF Symbols propios
- Versión Windows — fuera del alcance actual (roadmap del proyecto)

## Context

- **Codebase existente (brownfield):** `Sources/Klip/` ~30 archivos Swift. Puntos de integración para la captura ya analizados por agentes: `HotKey.swift` (reusable con `id:3`), `Settings.swift` (patrón `combo`/`voiceCombo`), `ClipboardManager.swift` (requiere nuevo método público `addAnnotatedScreenshot`), `PanelController.swift` (`KeyablePanel` reusable).
- **Modelo Gemini hoy:** hardcodeado en `GeminiClient.swift:8` (`gemini-flash-latest`). OpenAI ya tiene un `Picker` de modelo en `PreferencesView.swift:141` (patrón a replicar). Gemini muestra hoy `LabeledContent("Modelo", value: "gemini-flash-latest")` (PreferencesView.swift:145).
- **Spec de diseño revisado por agentes:** `docs/superpowers/specs/2026-06-17-klip-snap-captura-anotacion-design.md`.
- **Build/firma:** `install.sh` crea cert persistente `Klip Code Signing` e instala en `/Applications/Klip.app` → crítico para que TCC recuerde el permiso de pantalla entre recompilaciones.

## Constraints

- **Tech stack**: Swift 5.9 tools / target macOS 14, AppKit + SwiftUI, SwiftPM, compila solo con Command Line Tools (sin Xcode). No introducir dependencias externas.
- **Compatibility**: macOS 14 (Sonoma)+; probado en macOS 26 Apple Silicon. Captura vía ScreenCaptureKit (no `CGDisplayCreateImage`, deprecado).
- **Privacy**: local-first, sin telemetría, sin sandbox (entitlements vacío a propósito). Las API keys nunca en repo.
- **Timeline**: orientado a una demo de alto riesgo ante el dueño de Lightshot — priorizar robustez del flujo principal sobre features secundarias.
- **Signing/TCC**: usar `install.sh` (firma estable) e instalar en `/Applications`; nunca correr desde `.build/`.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| ScreenCaptureKit (`SCScreenshotManager`) | `CGDisplayCreateImage` deprecado en macOS reciente; one-shot ideal | — Pending |
| Modelo "freeze-frame" (capturar antes de mostrar overlay) | Evita auto-capturar el overlay y permite atenuar | — Pending |
| Editor en AppKit `NSView` custom (no SwiftUI Canvas) | Mejor hit-testing, texto in-place y `NSUndoManager` | — Pending |
| Texto in-canvas con `NSTextView` temporal | Maneja IME/acentos (ñ/á) gratis | — Pending |
| Iconos propios SF Symbols, NO los `.tiff` de Lightshot | IP de Skillbrains; framing de "evolución, no copia" ante el dueño | — Pending |
| Selector Gemini replica el `Picker` de OpenAI | Consistencia de UX y mínimo acoplamiento | — Pending |

---
*Last updated: 2026-06-17 after inicialización del proyecto GSD (milestone v0.5)*
