Confirmado todo lo que necesito. Datos clave verificados: i18n de Martin vive en `L10n.swift` (no `.lproj`, son 902 líneas añadidas), enums incompatibles (`AnnoTool` con `rect/highlight/pen` vs `SnapTool` con `rectangle/marker/pencil`), 10 archivos en conflicto, integración Snap en AppDelegate/PanelController/Settings. Tengo todo para el plan.

---

# PLAN DE INTEGRACIÓN KLIP — Rama Mike-Martin ↔ upstream/main (Snap de Martin)

## 1. Resumen ejecutivo

**¿Es factible?** Sí, pero NO con un `git merge` directo. El merge automático produce conflicto en **10 archivos** (verificado: `AnnotationView.swift`, `AppDelegate.swift`, `ClipboardManager.swift`, `GeminiClient.swift`, `HistoryView.swift`, `L10n.swift`, `PanelController.swift`, `PreferencesView.swift`, `Recorder.swift`, `Settings.swift`). El choque grave es estructural: Martin **borró `AnnotationView.swift`** (existe en disco, no en `upstream/main`) y lo partió en 6 archivos nuevos. Git no puede reconciliar "archivo borrado de un lado, modificado +386 líneas del otro" — requiere decisión humana.

**Esfuerzo aproximado:** **2.5–4 días** de un dev senior Swift/AppKit. Desglose:
- i18n de Martin (8 idiomas, +902 líneas en `L10n.swift`): adoptar casi tal cual, ~3h.
- 9 archivos solo-de-Martin (los 6 Snap + overlay + screencapturer + doc): entran limpios, ~0 conflicto.
- 29 archivos solo-nuestros (OAuth, EmailComposer, MailClient, Uploader, extensiones PanelController+*): entran limpios.
- El núcleo del trabajo: reconciliar el **anotador** y los puntos de integración (`AppDelegate`, `PanelController`, `Settings`, `L10n`), ~1.5–2.5 días.

**¿Qué arquitectura de anotador debería ganar?** **La de Martin (Snap), re-portando nuestras features encima.** Esto revierte la recomendación del consejo (que sugería conservar nuestro monolito). Razones:

1. **Martin va a seguir desarrollando sobre Snap.** Es upstream. Si conservamos nuestro `AnnotationView.swift` monolítico, divergimos permanentemente y cada futuro merge dolerá igual o más. Adoptar su arquitectura modular **paga la deuda una sola vez**.
2. **Su separación de responsabilidades es objetivamente mejor:** `ScreenCapturer` usa `ScreenCaptureKit` (macOS 14+) en vez del `CGDisplayCreateImage` deprecado; captura solo el display bajo el cursor (arregla bug multi-monitor); `CaptureOverlayController` y `SnapController` son piezas reutilizables.
3. **Nuestras features son portables como capas:** emoji picker, copy/paste, email-desde-anotador, redo, "deshacer Limpiar todo" son comportamientos que se re-aplican sobre `AnnotationCanvasView` + `SnapEditorController`. No requieren el monolito.

**Costo honesto de esta decisión:** re-portar nuestras features sobre Snap es **más trabajo** que conservar nuestro monolito (estimado +1 día vs Opción B del consejo). Es deuda técnica pagada por adelantado a cambio de cero divergencia futura con upstream. Si el plazo es agresivo y Martin NO va a tocar más el anotador, la Opción B (conservar nuestro monolito, adoptar solo nombres) es defendible como atajo. **Recomiendo Snap-gana** salvo presión de tiempo extrema.

---

## 2. Decisión por archivo

| Archivo | Conflicto | Qué conservar | Riesgo | Features nuestras a re-portar |
|---|---|---|---|---|
| `AnnotationView.swift` | Estructural (borrado vs +386L) | **Borrarlo. Gana Snap.** | **ALTO** | emoji picker, copy/paste texto+emoji, email-desde-anotador, redo (⌘⇧Z), "deshacer Limpiar todo", menú contextual, ⌘C/⌘V, flechas/Supr/Esc, `flattenedPNG()` Retina |
| `AnnotationModel.swift` (Martin) | Solo Martin | Suyo. Extender enum si falta algo nuestro | Bajo | Verificar que `SnapTool` cubre todas: tiene pencil/line/arrow/rectangle/ellipse/marker/text — **cubre nuestras 7** (nuestro `AnnoTool` mapea: pen→pencil, rect→rectangle, highlight→marker) |
| `AnnotationCanvasView.swift` (Martin) | Solo Martin | Suyo + **inyectar nuestras capas** | **ALTO** | copy/paste, redo, undo-reversible, atajos teclado, selección de texto |
| `SnapEditorController.swift` (Martin) | Solo Martin | Suyo + **botones nuestros** | **ALTO** | botón emoji, botón email, ⌘C/⌘V, ⌘Z/⌘⇧Z en su toolbar AppKit |
| `SnapController/CaptureOverlay/ScreenCapturer.swift` | Solo Martin | **Suyos tal cual** | Bajo | Ninguna (mejoras puras: ScreenCaptureKit, multi-monitor) |
| `AppDelegate.swift` | Ambos (+59L Martin) | **Merge manual** | **ALTO** | Wiring de OAuth, email, upload; + wiring Snap de Martin (`onCaptured` revela panel) |
| `PanelController.swift` | Ambos (−69L Martin) | **Nuestra versión** (@MainActor, extensiones, closers) + adoptar `onCaptureAnnotate` apuntando a Snap | **ALTO** | callbacks `onAnnotate/onUploadLink/onComposeEmail`, lifecycle de windows, error handling transcripción |
| `Settings.swift` | Ambos (+29L Martin) | **Merge manual** | Medio | Settings nuestros (email/OAuth) + de Martin (idioma, Snap) |
| `L10n.swift` | Ambos (+902L Martin) | **Base Martin** + claves nuestras | Medio | Claves de email/upload/anotador nuestras añadidas a sus 8 idiomas (o fallback a base) |
| `HistoryView.swift` | Ambos | **Nuestra versión** (3 callbacks nuevos) + iconos star/tag de Martin | Medio | onAnnotate/onUploadLink/onComposeEmail; adoptar fila de iconos de Martin |
| `ClipboardManager.swift` | Ambos | **Merge manual** | Medio | Inyección en `SnapController` (Martin guarda captura en historial) |
| `GeminiClient.swift` / `Recorder.swift` / `PreferencesView.swift` | Ambos | Merge línea-a-línea | Bajo-Medio | Revisar diffs; probablemente fixes de auditoría nuestros + ajustes Martin |
| 29 archivos solo-nuestros (OAuth, EmailComposer, MailClient, Uploader, PanelController+*) | Sin conflicto | **Todos nuestros** | Bajo | Entran limpios; verificar que compilan contra tipos renombrados |

---

## 3. Orden de operaciones del merge

Trabajar en rama dedicada, nunca sobre `Mike-Martin` directo.

```
1. git checkout Mike-Martin && git checkout -b integ/snap-merge
2. git merge upstream/main   # conflicto esperado en 10 archivos
```

**Fase A — Adoptar lo de Martin sin pelear (rápido):**
3. Aceptar **íntegros** los 9 archivos solo-de-Martin: los 6 Snap + `ScreenCapturer` + `CaptureOverlayController` + el doc design. `git checkout --theirs` para los que sean nuevos.
4. `L10n.swift`: tomar **base Martin** (`--theirs`), luego volver a inyectar nuestras claves (email/upload/anotador). i18n primero porque todo lo demás referencia claves.
5. Borrar `AnnotationView.swift` (`git rm`). Decisión: Snap gana.

**Fase B — Reconciliar puntos de integración (manual, cuidadoso):**
6. `Settings.swift`: merge manual — campos de idioma+Snap de Martin + email/OAuth nuestros.
7. `AppDelegate.swift`: merge manual — conservar nuestro wiring OAuth/email/upload, **añadir** el wiring Snap de Martin (`SnapController.onCaptured` → revelar panel). Punto crítico.
8. `PanelController.swift`: tomar **nuestra base** (@MainActor + extensiones + closers), pero apuntar el flujo de captura a `SnapController` en vez de a nuestro viejo `showAnnotationWindow`.
9. `HistoryView.swift`, `ClipboardManager.swift`, `GeminiClient.swift`, `Recorder.swift`, `PreferencesView.swift`: merge línea-a-línea conservando fixes de auditoría nuestros.

**Fase C — Re-portar features nuestras sobre Snap (el grueso):**
10. Sobre `AnnotationCanvasView.swift` y `SnapEditorController.swift`, re-implementar las 11 features de la sección 4.
11. `git rm` final de restos del monolito; resolver imports.

**Fase D — Compilar y validar (sección 5).**
12. `swift build` → selftest → e2e manual → commit por fases (no un commit gigante).

---

## 4. Features NUESTRAS a re-aplicar sobre la base de Snap (si Snap gana)

Estas son las que la refactorización de Martin **perdió** y hay que reconstruir sobre `AnnotationCanvasView` + `SnapEditorController`:

**Dentro del anotador (canvas/editor):**
1. **Emoji picker** — popover con 12 emojis (`["😀","👍","🔥","✅","❌","⭐️","➡️","❤️","⚠️","👀","🎯","💡"]`); inserta una `Annotation` `.text` movible/redimensionable. Botón nuevo en la toolbar AppKit de `SnapEditorController`.
2. **Copiar/pegar texto+emoji** — ⌘C: si hay anotación de texto seleccionada copia ESE texto, si no copia la imagen completa; ⌘V: pega texto/emoji como anotación nueva (desplazada si había selección). Reimplementar sobre el `mouseDown`/selección de `AnnotationCanvasView`.
3. **Email desde el anotador** — botón que llama al callback de `composeEmailWithImage` (usa `flattened()` de Martin) y cierra la ventana del editor.
4. **Redo completo** (⌘⇧Z) y **"deshacer Limpiar todo" reversible** — el undo de Martin es solo `removeLast` sin redo; reconstruir un stack undo/redo en `AnnotationCanvasView`.
5. **Menú contextual** con herramientas + atajos teclado avanzados (flechas mueven texto seleccionado, Supr borra, Esc cancela edición in-place).
6. **`flattenedPNG()` Retina** — Martin tiene `flattened()` que ya es Retina-aware; **verificar paridad** y usar el suyo; portar solo el wrapper de export si difiere. Revisar `isFlipped: false` de Martin vs nuestro `flipped: true` — esto afecta coordenadas de texto; testear.

**Features de producto fuera del anotador (NO tocadas por Snap, entran limpias pero hay que cablearlas):**
7. **Google Workspace OAuth per-usuario** — `GoogleOAuthClient.swift`, `GoogleSignInButton.swift` (sin conflicto; cablear en AppDelegate/Settings).
8. **Compositor de email multi-adjunto + MX inbox** — `EmailComposerView.swift`, `MailClient.swift`, `SystemMailSender.swift`, `PanelController+Email.swift`.
9. **Upload directo a link / visor web vestido** — `UploaderClient.swift`, `UploadView.swift`, `PanelController+Upload.swift`.
10. **"Ver en grande → anotar con lápiz"** sobre imagen existente — nuestro `annotateExistingImage`. Re-rutearlo para que abra `SnapEditorController` con la imagen ya cargada (en vez de captura nueva). `CapturePreviewController.swift`.
11. **Auditoría de 41 bugs** — son fixes dispersos en `ClipboardManager`, `Recorder`, `GeminiClient`, `Storage`, etc. **Riesgo de regresión:** revisar que el merge no revierta ninguno. Tener a mano la lista de los 41 para re-verificar.

---

## 5. Plan de pruebas post-merge

**Build / estático:**
- `swift build` limpio (sin warnings nuevos de tipos huérfanos del viejo `AnnotationView`).
- Verificar que **ningún** archivo referencia `AnnoTool`, `AnnotationCanvasNSView` ni `AnnotationView` (nombres viejos). `grep` esos símbolos → 0 resultados.
- `SelfTest.swift` pasa (ya existe en el repo).

**E2E manual del anotador (las 16 pruebas del consejo, prioritarias):**
- Captura ⌘⇧U abre overlay → seleccionar región → editor.
- Multi-monitor: capturar en pantalla secundaria (regresión que Snap arregla — validar).
- Dibujar las 7 herramientas (lápiz, línea, flecha, rectángulo, elipse, marcador, texto).
- Texto: doble-clic reedita, arrastrar mueve, A+/A− cambia tamaño, acentos funcionan.
- Emoji: abrir picker, insertar, mover.
- ⌘C copia texto seleccionado (no imagen); ⌘V pega; ⌘C sin selección copia imagen.
- Undo ⌘Z, Redo ⌘⇧Z, "Limpiar todo" + deshacer restaura.
- Flechas mueven, Supr borra, Esc cancela.
- Guardar PNG a resolución Retina (comparar dimensiones en píxeles físicos).
- Email desde anotador: cierra editor y abre compositor con imagen adjunta.

**E2E producto:**
- OAuth Google Workspace: login per-usuario, enviar email multi-adjunto, recibir respuesta detectada por token (MX inbox).
- Upload a link + abrir visor web vestido.
- "Ver en grande → anotar con lápiz" sobre imagen del historial.

**Regresión auditoría:**
- Re-correr verificación de los 41 bugs (al menos los de concurrencia/datos/integridad de rondas 5-7).

**i18n:**
- Cambiar a cada uno de los 8 idiomas; verificar que claves nuevas nuestras (email/upload/anotador) no muestran keys crudas.

---

## 6. Riesgos top y mitigación

| # | Riesgo | Severidad | Mitigación |
|---|---|---|---|
| 1 | **Re-portar features sobre Snap introduce bugs sutiles** (selección de texto, coordenadas `isFlipped`). El monolito ya funcionaba. | Alta | Portar feature-por-feature con commit atómico y test manual por cada una. NO portar todo y testear al final. Empezar por `isFlipped`/coordenadas (afecta a todo lo demás). |
| 2 | **Merge revierte fixes de la auditoría de 41 bugs** silenciosamente. | Alta | Antes del merge, exportar `git log -p` de los commits de auditoría a un archivo de referencia. Tras el merge, `git diff` contra ellos en `ClipboardManager`/`Recorder`/`GeminiClient`. |
| 3 | **Wiring AppDelegate ↔ SnapController ↔ PanelController mal conectado** (panel no se revela tras captura, o doble ventana). | Alta | Es el punto de integración #1. Probar el flujo completo captura→panel manualmente antes de seguir. Conservar el callback `onCaptured` de Martin. |
| 4 | **Decisión Snab-gana resulta ser más cara de lo estimado** y el plazo aprieta. | Media | Tener la **Opción B del consejo como fallback** (conservar nuestro monolito, adoptar solo nombres `SnapTool` y `struct Annotation` con `draw()`). Decidir tras Fase B: si re-portar features (Fase C) supera 1.5 días, pivotar a fallback. |
| 5 | **`L10n.swift` (+902L) genera ruido y oculta una clave faltante.** | Media | Tomar base Martin completa primero; añadir solo nuestras claves al final del archivo con fallback al idioma base; test de cambio de idioma obligatorio. |
| 6 | **Co-propiedad con Martin:** este merge altera SU arquitectura Snap (le añadimos capas). | Media | Por las instrucciones del proyecto (Klip es co-proyecto, no decidir solo sobre arquitectura): **consensuar con Martin** que Snap es la base y que re-portamos features encima, antes de invertir los 3 días. Idealmente vía PR a upstream para que él lo revise. |
| 7 | **`ScreenCaptureKit` exige macOS 14+** y permisos distintos al método viejo. | Baja | Ya es mejora de Martin; validar `hasPermission()`/`requestPermission()` en máquina limpia sin permisos previos. |

---

**Archivos clave (rutas absolutas):**
- Anotador que se borra: `/Users/MikeIbarra/Projects/Martin Velazco - COLAB/KLIP/Sources/Klip/AnnotationView.swift` (676 líneas, nuestro)
- Base Snap de Martin (entran limpios): `AnnotationModel.swift`, `AnnotationCanvasView.swift`, `SnapController.swift`, `SnapEditorController.swift`, `CaptureOverlayController.swift`, `ScreenCapturer.swift` en `/Users/MikeIbarra/Projects/Martin Velazco - COLAB/KLIP/Sources/Klip/`
- 10 archivos en conflicto verificado: `AnnotationView.swift`, `AppDelegate.swift`, `ClipboardManager.swift`, `GeminiClient.swift`, `HistoryView.swift`, `L10n.swift`, `PanelController.swift`, `PreferencesView.swift`, `Recorder.swift`, `Settings.swift`
- Features producto nuestras (sin conflicto): `GoogleOAuthClient.swift`, `GoogleSignInButton.swift`, `EmailComposerView.swift`, `MailClient.swift`, `SystemMailSender.swift`, `UploaderClient.swift`, `UploadView.swift`, `CapturePreviewController.swift`, y extensiones `PanelController+{Capture,Email,Upload,Voice,Actions,Export,Keyboard}.swift`

**Datos verificados contra el repo:** merge-base `21f4b65`; Martin borró `AnnotationView.swift` (confirmado: no existe en `upstream/main`); `SnapTool` de Martin cubre las 7 herramientas nuestras (mapeo pen→pencil, rect→rectangle, highlight→marker); i18n de Martin vive en `L10n.swift` (+902L), no en `.lproj`; Snap toca AppDelegate (+59L), PanelController (−69L), Settings (+29L).

**Una corrección honesta al consejo:** su recomendación por-archivo era "portar-lo-nuestro-sobre-lo-de-martin" conservando NUESTRO monolito (Opción B). Yo recomiendo lo inverso para el anotador: **adoptar la arquitectura Snap de Martin y re-portar nuestras features encima**, porque Martin es upstream y conservar el monolito garantiza divergencia permanente. Es más trabajo ahora (~+1 día) a cambio de cero deuda de merge futura. Esta decisión debe consensuarse con Martin por ser cambio arquitectónico en co-proyecto.
