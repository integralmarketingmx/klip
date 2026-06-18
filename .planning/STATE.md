# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-17)

**Core value:** Todo lo que copias (o capturas) queda persistente y buscable, a un atajo de distancia, sin salir de tu Mac.
**Current focus:** Phase 1 — Selector de modelo Gemini

## Current Position

Phase: 1 of 4 (Selector de modelo Gemini)
Plan: 0 of TBD in current phase
Status: Ready to plan
Last activity: 2026-06-17 — ROADMAP.md creado para milestone v0.5 (4 fases, 18/18 requisitos mapeados)

Progress: [░░░░░░░░░░] 0%

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
