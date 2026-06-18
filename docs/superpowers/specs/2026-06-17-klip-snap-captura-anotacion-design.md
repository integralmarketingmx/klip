# Klip Snap — Captura y anotación de pantalla (estilo Lightshot)

**Fecha:** 2026-06-17
**Estado:** Diseño revisado por agentes (arquitectura, integración, UX). Pendiente de aprobación del usuario.
**Objetivo:** Integrar en Klip un flujo de captura de región + editor de anotaciones equivalente a Lightshot, para una demo ante el dueño de Lightshot.

---

## 1. Resumen

Klip es una app de barra de menú (macOS 14+, Swift/AppKit + SwiftUI, SwiftPM sin Xcode) con historial de portapapeles, OCR (Vision) y notas de voz. Esta función añade:

1. **Captura de región** mediante atajo global (`⌘⇧2`, configurable) con overlay "freeze-frame" y badge de dimensiones en vivo.
2. **Editor de anotaciones** (AppKit `NSView` custom) con toolbar flotante: lápiz, línea, flecha, rectángulo, elipse, marcador, texto, color, grosor, deshacer.
3. **Copiar / Guardar** → la imagen anotada **entra al historial persistente de Klip** (con OCR y búsqueda disponibles, como cualquier imagen).

**Diferenciador clave (gancho de la demo):** a diferencia de Lightshot, que pierde la captura al cerrar, en Klip cada screenshot queda en el historial persistente y es **buscable por su contenido vía OCR**. *"Lightshot es el momento; Klip es el momento + memoria."*

## 2. Alcance

**Incluye:**
- Overlay de selección de región (multi-monitor) con badge de dimensiones.
- Editor con herramientas: lápiz, línea, flecha, rectángulo, elipse, marcador (resaltador), texto, selector de color, grosor, deshacer (⌘Z).
- Acciones: Copiar (⌘C), Guardar a archivo (⌘S), Cerrar (Esc).
- Inserción de la imagen anotada al historial de Klip.
- Gestión del permiso TCC de Grabación de pantalla.

**Excluye (YAGNI para la demo; pendiente/roadmap):**
- Subir a URL pública (prntscr.com), compartir en redes, buscar en Google Images, imprimir.

## 3. Arquitectura

Archivos nuevos en `Sources/Klip/`:

| Archivo | Responsabilidad |
|---|---|
| `ScreenCapturer.swift` | Captura bitmap de pantallas vía **ScreenCaptureKit** (`SCShareableContent` + `SCScreenshotManager.captureImage`, macOS 14+). Gating de permiso con `CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()`. Warm-up al arranque. |
| `CaptureOverlayController.swift` | Ventana borderless por monitor (reusa patrón `KeyablePanel`). Muestra el screenshot estático atenuado (freeze-frame), selección por arrastre, badge de dimensiones en vivo, `Esc` cancela; mouse-up recorta y abre el editor. |
| `AnnotationModel.swift` | Modelo de anotaciones (tipo, puntos, color, grosor, texto) + pila de undo (`NSUndoManager`). |
| `AnnotationCanvasView.swift` | `NSView` que renderiza imagen base + anotaciones; dibujo en vivo (`mouseDown/Dragged/Up`), hit-testing, redibujo de dirty rect. Texto con `NSTextView` temporal superpuesto. |
| `SnapEditorController.swift` | Ventana del editor + toolbar flotante (SF Symbols). Acciones copiar/guardar; empuja el resultado a `ClipboardManager`. |

**Integración en código existente:**
- `HotKey.swift` — reusar con `id: 3` para `⌘⇧2` (Carbon `RegisterEventHotKey`, sin permiso de Accesibilidad).
- `Settings.swift` — añadir `captureCombo` (patrón idéntico a `combo`/`voiceCombo`).
- `AppDelegate.swift` — ítem de menú "Capturar región" + cableado del hotkey en `setupHotKeys()`.
- `ClipboardManager.swift` — **nuevo método público** `addAnnotatedScreenshot(_ image: NSImage, annotations: String?)` (las imágenes hoy se insertan solo de forma privada al monitorear el pasteboard). `Storage.saveImage/pngData` ya son públicos.

## 4. Flujo de datos

1. Hotkey/menu → `ScreenCapturer` captura full-display (ANTES de mostrar overlay) → `CGImage` por display.
2. `CaptureOverlayController` muestra cada captura estática atenuada → usuario arrastra región (badge en vivo).
3. mouse-up → recorta el `CGImage` al rect seleccionado (escalado por `backingScaleFactor`) → abre `SnapEditorController` con la región.
4. Usuario anota (`AnnotationModel` + `AnnotationCanvasView`).
5. Copiar/Guardar → se "aplana" la imagen anotada → `ClipboardManager.addAnnotatedScreenshot(...)` → entra al historial (OCR/búsqueda disponibles).

## 5. Decisiones técnicas (validadas por revisión de agentes)

- **ScreenCaptureKit** (no `CGDisplayCreateImage`, deprecado en macOS reciente). `SCScreenshotManager.captureImage` para one-shot; **no** mantener `SCStream` vivo.
- **Modelo freeze-frame**: capturar primero, mostrar estático; evita auto-capturar el overlay y permite atenuar.
- **Multi-monitor / Retina**: una ventana overlay por `NSScreen`; emparejar `NSScreen`↔`SCDisplay` por `displayID` (`NSScreenNumber`); escalar rects por `backingScaleFactor`; configurar `SCStreamConfiguration.width/height` en píxeles físicos.
- **Editor en AppKit** `NSView` custom (no SwiftUI Canvas): mejor para hit-testing, edición de texto in-place y `NSUndoManager`.
- **Texto in-canvas con `NSTextView` temporal** superpuesto (maneja IME/acentos `ñ`/`á`), luego flatten al confirmar.
- **Firma estable**: usar `install.sh` (cert `Klip Code Signing`) e instalar en `/Applications/Klip.app` para que TCC recuerde el permiso entre recompilaciones. Nunca correr desde `.build/`.
- **`Package.swift`**: añadir `.linkedFramework("ScreenCaptureKit")`. Sin App Sandbox (entitlements vacío a propósito).
- **Iconos propios (SF Symbols)** — NO reutilizar los `.tiff` de Lightshot (IP de Skillbrains).

## 6. Permisos y errores

- **Grabación de pantalla (TCC):** verificar con `CGPreflightScreenCaptureAccess()`; si falta, mostrar onboarding claro y `CGRequestScreenCaptureAccess()`. Autorizar antes de la demo.
- **Captura vacía / sin displays:** abortar con aviso, no crashear.
- **Selección de tamaño 0 / Esc:** cancelar limpio, cerrar overlays.
- **Latencia del primer disparo:** warm-up de `SCShareableContent.current` al arrancar.

## 7. Riesgos (orden de probabilidad de hundir la demo)

1. **TCC olvida el permiso** por firma/ruta inestable → usar cert persistente + `/Applications` + autorizar antes.
2. **Recorte a escala incorrecta en Retina/multi-monitor** → escalar por `backingScaleFactor`, emparejar por `displayID`; probar en monitor externo + interno.
3. **El overlay se auto-captura o no aparece sobre fullscreen** → freeze-frame (capturar antes), `collectionBehavior` `.canJoinAllSpaces`/`.fullScreenAuxiliary`, nivel `CGShieldingWindowLevel()`.
4. **Edición de texto rota con acentos** → `NSTextView` temporal; probar `ñ/á`.
5. **Lag del primer disparo de SCK** → warm-up al arranque.

## 8. UX imprescindible vs nice-to-have

- **Imprescindible:** badge de dimensiones en vivo · toolbar flotante anclada al borde de la selección · feedback al copiar (toast + item "vuela" al historial) · edición de texto in-place (doble clic) · undo responsivo · crosshair de selección.
- **Nice-to-have:** lupa de precisión al seleccionar · animaciones de entrada del toolbar · color picker desplegable.

## 9. Guion de demo (60s)

1. `⌘⇧2` → pantalla se atenúa, crosshair.
2. Arrastra región → **badge de dimensiones sigue al cursor**; suelta → toolbar se ancla con animación.
3. Flecha → rectángulo → doble clic + texto in-place → cambia color → **undo**.
4. **Copiar** → toast "Copiado" + el screenshot **vuela al historial de Klip**.
5. Abrir historial → la captura sigue ahí → **buscar una palabra que estaba DENTRO de la imagen → aparece por OCR**. (Momento *wow*, cierre.)
6. Frase de cierre: *"Tu flujo de captura, ahora con memoria y búsqueda."*

## 10. Criterios de éxito

- `⌘⇧2` dispara captura de región en cualquier monitor con escala correcta.
- El editor permite las 7 herramientas + color + undo, con texto que acepta acentos.
- Copiar/Guardar produce un PNG anotado fiel a lo dibujado.
- La captura anotada aparece en el historial de Klip y es recuperable por OCR/búsqueda.
- El permiso de pantalla se solicita una sola vez y se recuerda entre recompilaciones (vía install.sh).
