# Roadmap: Klip — v0.5 "Captura nativa + control de transcripción"

## Overview

Este milestone evoluciona Klip de un gestor de portapapeles a una herramienta de captura con memoria. El recorrido empieza por una victoria temprana y de bajo riesgo (selector de modelo Gemini, replicando un patrón ya existente), luego construye el músculo nativo más arriesgado (captura de región con ScreenCaptureKit, freeze-frame y permiso TCC), sobre él monta el editor de anotaciones AppKit (las 7 herramientas + texto con acentos + undo), y finalmente cierra el lazo conectando la captura anotada con el historial persistente/OCR de Klip y puliendo el guion de demo de 60s ante el dueño de Lightshot. El gancho de la demo —"Lightshot es el momento; Klip es el momento + memoria"— solo es verificable cuando las cuatro fases están completas, pero cada fase entrega valor observable por sí misma.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Selector de modelo Gemini** - Picker de modelo en Preferencias, persistido y consumido por GeminiClient ✅
- [x] **Phase 2: Captura de región + permiso TCC** - Overlay freeze-frame multi-monitor/Retina vía ScreenCaptureKit con gating de permiso ✅
- [x] **Phase 3: Editor de anotaciones** - NSView custom con 7 herramientas, texto con acentos, color/grosor, undo, copiar/guardar ✅
- [x] **Phase 4: Integración con historial + pulido de demo** - Captura anotada entra al historial persistente con OCR/búsqueda y feedback al copiar ✅

## Phase Details

### Phase 1: Selector de modelo Gemini
**Goal**: El usuario puede elegir qué modelo de Google Gemini usa Klip para transcribir voz, reemplazando el valor hoy fijo `gemini-flash-latest`.
**Depends on**: Nothing (first phase)
**Requirements**: GEM-01, GEM-02, GEM-03
**Success Criteria** (what must be TRUE):
  1. En Preferencias aparece un `Picker` de modelo Gemini (consistente con el de OpenAI en `PreferencesView.swift:141`), en lugar del `LabeledContent` fijo actual
  2. La lista incluye al menos `gemini-flash-latest` (predeterminado), `gemini-2.5-flash` y `gemini-2.5-pro`
  3. La selección persiste en `Settings`/`UserDefaults` y sobrevive a reiniciar la app
  4. Al transcribir una nota de voz, `GeminiClient` usa el modelo seleccionado (ya no el hardcodeado en `GeminiClient.swift:8`)
**Risk note**: Riesgo bajo. Patrón ya probado (OpenAI). Único cuidado: usar el mismo mecanismo de persistencia que `combo`/`voiceCombo` para no fragmentar la configuración.
**Plans**: TBD

### Phase 2: Captura de región + permiso TCC
**Goal**: El usuario dispara una captura de región nativa con overlay tipo Lightshot que funciona en cualquier monitor a la escala correcta, con el permiso de Grabación de pantalla gestionado.
**Depends on**: Phase 1 (secuencial por orden de roadmap; técnicamente independiente)
**Requirements**: CAP-01, CAP-02, CAP-03, CAP-04, CAP-05, CAP-06
**Success Criteria** (what must be TRUE):
  1. `⌘⇧2` (configurable vía `captureCombo`) y un ítem de menú de Klip disparan la captura, reusando `HotKey` con `id:3`
  2. La pantalla se muestra como freeze-frame atenuado por monitor y el usuario arrastra para seleccionar una región con crosshair
  3. Durante el arrastre se ve un badge con las dimensiones en vivo (ancho × alto) que sigue al cursor
  4. El recorte sale a la escala/píxeles correctos en pantallas Retina y en multi-monitor (emparejando `NSScreen`↔`SCDisplay` por `displayID`, escalando por `backingScaleFactor`)
  5. `Esc` o una selección de tamaño cero cancela limpiamente cerrando todos los overlays
  6. Si falta el permiso TCC, Klip lo detecta (`CGPreflightScreenCaptureAccess()`) y muestra un onboarding claro que lo solicita
**Risk note**: Fase de mayor riesgo de la demo. (1) TCC olvida el permiso si la firma/ruta es inestable → instalar vía `install.sh` en `/Applications` y autorizar antes. (2) Recorte mal escalado en Retina/multi-monitor → escalar por `backingScaleFactor`, probar monitor interno + externo. (3) Overlay se auto-captura o no sale sobre fullscreen → freeze-frame (capturar antes), `collectionBehavior` `.canJoinAllSpaces`/`.fullScreenAuxiliary`, `CGShieldingWindowLevel()`. (4) Lag del primer disparo de SCK → warm-up de `SCShareableContent.current` al arranque. Requiere `.linkedFramework("ScreenCaptureKit")` en `Package.swift`.
**Plans**: TBD

### Phase 3: Editor de anotaciones
**Goal**: Al soltar la selección, el usuario anota la captura con un editor AppKit completo (herramientas de dibujo, texto in-place, color/grosor, undo) y puede copiarla o guardarla.
**Depends on**: Phase 2 (necesita la región recortada que produce la captura)
**Requirements**: EDI-01, EDI-02, EDI-03, EDI-04, EDI-05, EDI-06
**Success Criteria** (what must be TRUE):
  1. Al soltar la selección se abre un editor con la región recortada y una toolbar flotante de iconos SF Symbols anclada al borde de la selección
  2. El usuario puede dibujar con lápiz, línea, flecha, rectángulo, elipse y marcador (resaltador)
  3. El usuario puede añadir texto in-place con doble clic que acepta acentos (ñ/á) vía `NSTextView` temporal superpuesto
  4. El usuario puede elegir color y grosor del trazo, y deshacer (`⌘Z`) las anotaciones de forma responsiva
  5. El usuario puede copiar (`⌘C`), guardar a archivo (`⌘S`) y cerrar (`Esc`), produciendo un PNG aplanado fiel a lo dibujado
**Risk note**: Editor en `NSView` custom (no SwiftUI Canvas) para hit-testing y `NSUndoManager`. Riesgo principal: la edición de texto se rompe con acentos → usar `NSTextView` temporal y probar `ñ/á` explícitamente. Iconos propios SF Symbols, NO los `.tiff` de Lightshot (IP de Skillbrains).
**Plans**: TBD
**UI hint**: yes

### Phase 4: Integración con historial + pulido de demo
**Goal**: La captura anotada entra al historial persistente y buscable de Klip, con feedback claro al copiar, cerrando el gancho diferenciador de la demo.
**Depends on**: Phase 3 (necesita la imagen anotada aplanada)
**Requirements**: HIS-01, HIS-02, HIS-03
**Success Criteria** (what must be TRUE):
  1. Al copiar o guardar, la imagen anotada se inserta en el historial vía el nuevo método público `addAnnotatedScreenshot(_ image: NSImage, annotations: String?)` de `ClipboardManager`
  2. La captura anotada queda disponible para OCR y búsqueda como cualquier otra imagen del historial (buscar una palabra que está DENTRO de la imagen la encuentra)
  3. Al copiar se muestra feedback claro (toast "Copiado") y el item aparece en el historial
  4. El guion de demo de 60s del spec corre de principio a fin sin fallos (`⌘⇧2` → anotar → copiar → toast → historial → búsqueda por OCR)
**Risk note**: Las imágenes hoy se insertan solo de forma privada al monitorear el pasteboard; el método público es nuevo. `Storage.saveImage/pngData` ya son públicos. El "momento wow" depende de que el OCR (Vision, v0.4) indexe la captura recién insertada; validar que el pipeline existente la procesa. Validar el guion completo en hardware de demo antes del día.
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Selector de modelo Gemini | 0/TBD | Not started | - |
| 2. Captura de región + permiso TCC | 0/TBD | Not started | - |
| 3. Editor de anotaciones | 0/TBD | Not started | - |
| 4. Integración con historial + pulido de demo | 0/TBD | Not started | - |
