# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-17)

**Core value:** Todo lo que copias (o capturas) queda persistente y buscable, a un atajo de distancia, sin salir de tu Mac.
**Current focus:** Milestone v0.5 implementado — desplegado vía install.sh

## Current Position

Phase: 4 of 4 completas (Selector Gemini · Captura+TCC · Editor · Integración historial)
Plan: implementación autónoma (sin descomposición en sub-planes; código directo + review de agente)
Status: Implementado, compila (swift build OK), desplegado en /Applications vía install.sh
Last activity: 2026-06-17 — 4 fases implementadas, code review aplicado (4 fixes), deploy

Progress: [██████████] 100% (implementación) — pendiente validación humana del flujo de captura en vivo

### Validación humana pendiente (requiere interacción del usuario)
- Conceder permiso de Grabación de pantalla a Klip la primera vez (⌘⇧2)
- Probar selección en monitor interno (Retina) y externo
- Confirmar texto con acentos (ñ/á) en el editor
- Verificar que la captura entra al historial y el OCR la indexa

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: — min
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: —
- Trend: —

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Phase 1]: Selector Gemini replica el `Picker` de OpenAI (consistencia UX, mínimo acoplamiento)
- [Phase 2]: ScreenCaptureKit (`SCScreenshotManager`) en vez de `CGDisplayCreateImage` (deprecado); modelo freeze-frame
- [Phase 3]: Editor en AppKit `NSView` custom + texto in-place con `NSTextView` temporal (acentos)

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 2]: TCC del permiso de pantalla es el mayor riesgo de la demo — instalar vía `install.sh` en `/Applications` y autorizar antes; nunca correr desde `.build/`
- [Phase 2]: Recorte a escala correcta en Retina/multi-monitor — validar en monitor interno + externo
- [Phase 4]: Validar que el OCR (Vision) indexa la captura recién insertada al historial antes de la demo

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Compartir/Subir | SHR-01..04 (URL pública, redes, Google Images, imprimir) | Deferred to v2 | 2026-06-17 |

## Session Continuity

Last session: 2026-06-17
Stopped at: ROADMAP.md y STATE.md creados; traceability confirmada
Resume file: None
