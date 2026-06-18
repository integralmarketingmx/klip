# Requirements: Klip — Milestone v0.5 "Captura nativa + control de transcripción"

**Defined:** 2026-06-17
**Core Value:** Todo lo que copias (o capturas) queda persistente y buscable, a un atajo de distancia, sin salir de tu Mac.

## v1 Requirements (milestone v0.5)

### Captura de pantalla (CAP)

- [x] **CAP-01**: El usuario dispara la captura de región con un atajo global (`⌘⇧2` por defecto) y desde un ítem del menú de Klip
- [x] **CAP-02**: La pantalla se muestra como imagen estática atenuada (freeze-frame) sobre la que el usuario arrastra para seleccionar una región
- [x] **CAP-03**: Durante la selección se muestra un badge con las dimensiones en vivo (ancho × alto)
- [x] **CAP-04**: La captura funciona correctamente en multi-monitor y en pantallas Retina (recorte a la escala/píxeles correctos)
- [x] **CAP-05**: `Esc` o una selección de tamaño cero cancela la captura limpiamente
- [x] **CAP-06**: Si falta el permiso de Grabación de pantalla, Klip lo detecta y muestra un onboarding claro para concederlo

### Editor de anotaciones (EDI)

- [x] **EDI-01**: Al soltar la selección se abre un editor con la región recortada y una toolbar flotante (iconos SF Symbols)
- [x] **EDI-02**: El usuario puede dibujar con: lápiz, línea, flecha, rectángulo, elipse y marcador (resaltador)
- [x] **EDI-03**: El usuario puede añadir texto in-place (doble clic) que acepta acentos (ñ/á) vía `NSTextView` temporal
- [x] **EDI-04**: El usuario puede elegir color y grosor del trazo
- [x] **EDI-05**: El usuario puede deshacer (`⌘Z`) las anotaciones
- [x] **EDI-06**: El usuario puede copiar (`⌘C`), guardar a archivo (`⌘S`) y cerrar (`Esc`) la captura anotada

### Integración con el historial (HIS)

- [x] **HIS-01**: Al copiar o guardar, la imagen anotada se inserta en el historial persistente de Klip vía un método público nuevo en `ClipboardManager`
- [x] **HIS-02**: La captura anotada queda disponible para OCR y búsqueda como cualquier otra imagen del historial
- [x] **HIS-03**: Al copiar se muestra feedback claro (toast/confirmación) y el item aparece en el historial

### Selector de modelo Gemini (GEM)

- [x] **GEM-01**: En Preferencias, el usuario elige el modelo de Google Gemini desde un `Picker` (reemplaza el valor fijo `gemini-flash-latest`)
- [x] **GEM-02**: La selección persiste en `Settings`/`UserDefaults` y la usa `GeminiClient` al transcribir
- [x] **GEM-03**: La lista incluye al menos los modelos vigentes (p. ej. `gemini-flash-latest`, `gemini-2.5-flash`, `gemini-2.5-pro`) con `gemini-flash-latest` como predeterminado

## v2 Requirements (deferred)

### Compartir / Subir (SHR)

- **SHR-01**: Subir la captura a una URL pública compartible
- **SHR-02**: Compartir en redes (Twitter/Facebook/Pinterest/VK)
- **SHR-03**: Buscar la imagen en Google Images
- **SHR-04**: Imprimir la captura

## Out of Scope

| Feature | Reason |
|---------|--------|
| Subir/compartir/buscar/imprimir | Fuera de la demo; requieren backend o IP de terceros — diferidos a v2 |
| Reutilizar assets `.tiff` de Lightshot | IP de Skillbrains; se usan SF Symbols propios |
| SCStream en vivo / grabación de video | El flujo es one-shot; `SCScreenshotManager` basta |
| Versión Windows | Fuera del alcance del producto por ahora |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| GEM-01 | Phase 1 | Done |
| GEM-02 | Phase 1 | Done |
| GEM-03 | Phase 1 | Done |
| CAP-01 | Phase 2 | Done |
| CAP-02 | Phase 2 | Done |
| CAP-03 | Phase 2 | Done |
| CAP-04 | Phase 2 | Done |
| CAP-05 | Phase 2 | Done |
| CAP-06 | Phase 2 | Done |
| EDI-01 | Phase 3 | Done |
| EDI-02 | Phase 3 | Done |
| EDI-03 | Phase 3 | Done |
| EDI-04 | Phase 3 | Done |
| EDI-05 | Phase 3 | Done |
| EDI-06 | Phase 3 | Done |
| HIS-01 | Phase 4 | Done |
| HIS-02 | Phase 4 | Done |
| HIS-03 | Phase 4 | Done |

**Coverage:**
- v1 requirements: 18 total
- Mapped to phases: 18
- Unmapped: 0 ✓

---
*Requirements defined: 2026-06-17*
*Last updated: 2026-06-17 after inicialización del milestone v0.5*
