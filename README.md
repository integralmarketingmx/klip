<div align="center">

# 📋 Klip

**El portapapeles para vibe coders, nativo para Mac.** Todo lo que copias para programar con IA —código, errores, capturas, prompts y claves— a un atajo de distancia.

Historial de texto e imágenes · **captura + anotación nativa** · **OCR** · **notas de voz → texto** (OpenAI o Gemini) · **copiar como bloque de código** · **combinar contexto en PDF/ZIP** · gestor de credenciales. Vive en la barra de menú: ligero, rápido y privado.

🆓 Gratis y open source (MIT) · 🔒 Sin telemetría · 🍎 Swift nativo (sin Electron)

<br/>

<img src="docs/klip-preview.gif" alt="Klip en acción: recortar una zona de la pantalla, que aparezca en Klip y extraer su texto con OCR; y grabar una nota de voz que se transcribe sola" width="500"/>

<sub>Recorta una zona → aparece en Klip → extrae el texto (OCR) · y graba una nota de voz que se transcribe sola.</sub>

</div>

> ### 🖥️ Por ahora, solo para Mac
> Klip es una app **nativa de macOS** y requiere **macOS 14 (Sonoma) o superior** (Apple Silicon o Intel).
> La versión para **Windows 🪟 llegará más adelante**. Tus datos se quedan en tu equipo.

---

## 🤔 ¿Por qué Klip si programas con IA?

El "vibe coding" es un ir y venir constante de copiar y pegar entre tu editor y herramientas como Claude, ChatGPT o Cursor: snippets de código, mensajes de error, capturas de la UI, salidas de terminal, prompts dictados y API keys. Klip está pensado para ese flujo:

- **Nunca pierdes un snippet** — todo lo que copias queda en un historial buscable.
- **Capturas un error y lo anotas** (flechas, texto, marcador) sin salir del teclado, y entra a Klip listo para pegar en la IA.
- **Sacas el texto de una captura** (OCR) para pegar un log que estaba en imagen.
- **Copias como bloque de código** (` ``` `) para pegar limpio en un chat.
- **Dictas un prompt** y Klip lo transcribe a texto.
- **Juntas varios clips** (capturas + textos) en un **PDF o ZIP** para subirlos de una sola vez como contexto.
- **Guardas tus API keys** detectadas y enmascaradas, con nombre y búsqueda.

## ✨ Funciones

### 📋 Portapapeles
- **Historial automático** de **texto e imágenes/capturas**.
- **Búsqueda** instantánea con **resaltado** de coincidencias + **navegación por teclado** (↑/↓, Enter, `⌘1`–`⌘9`, `Esc`).
- **Filtros** por tipo (texto · imágenes · voz · credenciales · fijados); los chips de tipo solo aparecen cuando hay elementos de ese tipo.
- **Pegado automático** en la app activa · **Fijar** 📌 · **Eliminar** 🗑️ (con confirmación al borrar todo).
- **Fecha legible** en cada elemento: *"martes 04 de julio · 10:43"*, *"Hoy"*, *"Ayer"*.

### 📸 Captura + anotación nativa (Klip Snap)
- Atajo global **`⌘⇧U`** → recorta una región de la pantalla (selección con el ratón sobre un *freeze-frame* atenuado, con badge de dimensiones en vivo y escala Retina correcta). Usa **ScreenCaptureKit** (no la API deprecada).
- **Editor de anotación** integrado: lápiz, línea, **flecha**, rectángulo, elipse, marcador, **texto editable/movible/redimensionable**, color, grosor y **deshacer**.
- Al terminar, la captura anotada entra al **historial** (queda lista para **OCR** y búsqueda) y al portapapeles.
- También desde el botón 📷 del panel o el menú de la barra de estado.

### 🖼️ Imágenes
- Previsualización grande (miniaturas en caché para que el scroll vaya fluido), **abrir en grande** y **guardar como archivo**.
- **OCR** (extraer texto de una imagen) con el motor **Vision** de Apple — gratis y en el dispositivo. Ideal para sacar el texto de un log o error que copiaste como captura.

### 🎙️ Notas de voz → texto
- **Graba** (`⌘⇧I`) o **sube un archivo** (m4a, mp3, wav, **.opus de WhatsApp**, ogg, flac…).
- Se transcribe **en segundo plano** — puedes grabar otra al instante.
- **El audio original se guarda** con **duración** y **barra de progreso**: lo reproduces (▶) o lo abres en Finder, y puedes **reintentar (↻)** si la transcripción falla.

### 🤖 IA: tú eliges el motor
- **OpenAI** o **Google Gemini** para la transcripción. Pones tu propia clave de cualquiera de los dos.
- Para **Gemini** puedes elegir el modelo (`gemini-flash-latest`, `-flash-lite-latest`, `-pro-latest`, `2.5-flash`, `2.5-pro`); para **OpenAI**, `gpt-4o-mini-transcribe` o `whisper-1`.

### 🧰 Pensado para pegar en la IA
- **Copiar como bloque de código** — envuelve el texto en ` ``` ` para pegarlo limpio en un chat.
- **Copiar como Markdown** un elemento, o exportar **todo el historial** a Markdown.
- **Guardar texto como archivo** (`.txt`/`.md`) para arrastrarlo a una herramienta cuando el chat no acepta pegarlo.
- **Multi-selección por lote** (icono ☑️ del encabezado): marca varios clips y…
  - **Combínalos en un PDF** (una página por captura/texto) para subir un contexto completo de una vez.
  - **Expórtalos como ZIP** (subset elegido, distinto del ZIP de copia de seguridad).
  - **Asígnalos a una colección**.

### 🏷️ Organización
- **Colecciones** — agrupa clips relacionados (p. ej. el contexto de una tarea) y fíltralos con un chip.
- **Ponle nombre a cualquier elemento** y búscalo por ese nombre (ideal para tus credenciales).
- **Acciones por tipo**: **abrir enlaces** 🔗 y **muestra de color** para valores hex (`#1E90FF`).
- **Mini gestor de credenciales** 🔑: detecta tokens y API keys al copiarlos, los guarda **enmascarados** (👁 para revelar/copiar), con su propio filtro. No se autopegan (se copian para que las pegues a mano, por seguridad).

### 💾 Copia de seguridad
- **Exportar / importar** todo el historial (imágenes y audio incluidos) en un `.zip`. **Nunca** incluye tus claves de API.

### 🔒 Privacidad y sistema
- Todo **local** con permisos `0600` · **sin telemetría** · ignora contraseñas y permite **excluir apps**.
- **Firma estable**: macOS te pide los permisos (micrófono, grabación de pantalla…) **una sola vez** y los recuerda entre actualizaciones.
- **Arranque al iniciar sesión** opcional · 🌍 **Español / Inglés**.

## ⌨️ Atajos

| Atajo | Acción |
|---|---|
| `⌘⇧E` | Abrir el panel del historial |
| `⌘⇧I` | Grabar / detener una nota de voz |
| `⌘⇧U` | **Capturar y anotar** una región (Klip Snap) |
| `↑` / `↓` · `Enter` | Navegar y elegir un elemento |
| `⌘1`–`⌘9` | Elegir (y pegar) el elemento Nº 1–9 |
| `Esc` | Cerrar el panel |
| `⌘⇧⌃4` | *(de macOS)* captura al portapapeles → también entra a Klip |

> Los tres atajos globales (`⌘⇧E`, `⌘⇧I`, `⌘⇧U`) son **configurables** en Preferencias › Atajos.
> Se usa una **letra** (`U`) y no un número: `⌘⇧2` lo secuestraban otras apps (p. ej. Loom), y `⌘⇧3`/`4`/`5` son las capturas del sistema.

## 🧰 Requisitos

- **macOS 14 (Sonoma) o superior** — probado en macOS 26, Apple Silicon.
- **Command Line Tools de Xcode** (no hace falta Xcode completo):
  ```bash
  xcode-select --install
  ```
- *(Opcional)* Una **API key de OpenAI o Google Gemini** para las notas de voz. Se guarda en un **archivo local** de la app, nunca en el código ni en el repositorio.

## ⚡ Instalación rápida

```bash
git clone https://github.com/tamibot/klip.git klip
cd klip
./install.sh
```

Eso compila Klip, lo firma, lo copia a `/Applications`, lo lanza y registra el arranque al inicio.
Verás el icono 📋 en la barra de menú. Pulsa **`⌘⇧E`** para abrir el historial.

> La primera vez, `install.sh` crea un **certificado de firma local** (`Klip Code Signing`) en tu Llavero para que la firma sea estable. Así macOS te pide los permisos (micrófono, accesibilidad, grabación de pantalla) **una sola vez** y los recuerda entre actualizaciones, en lugar de volver a preguntar en cada reinstalación. Es local y reversible (puedes borrarlo desde *Acceso a Llaveros*).
>
> macOS puede pedir aprobar el "ítem de inicio de sesión" en *Ajustes › General*. Para el **pegado automático**, concede Accesibilidad cuando se solicite (menú de Klip → *Activar pegado automático…*). La primera captura con `⌘⇧U` pedirá **Grabación de pantalla**.

### Compilar sin instalar

```bash
./build.sh        # genera Klip.app en la carpeta del proyecto
open Klip.app
```

### Desarrollo

```bash
swift build       # compilación de depuración
swift run Klip    # ejecuta directamente
```

## 🚀 Uso (flujo típico de un vibe coder)

1. **Copia lo que sea** mientras programas (código, salida de terminal, un mensaje de error). Todo queda en Klip.
2. **`⌘⇧E`** → abre el panel. Escribe para **buscar**; usa **↑/↓ + Enter** o haz **clic** para elegir un elemento (se pega solo si activaste el pegado automático).
3. Para pegar código en un chat de IA, pasa el cursor sobre la fila y pulsa **`</>`** (*copiar como bloque de código*).
4. **`⌘⇧U`** → recorta el error/UI de la pantalla, anótalo (flecha + texto) y entra a Klip. Pásale el cursor y pulsa **OCR** si quieres su texto.
5. 🎙️ **`⌘⇧I`** para dictar un prompt; al detener, se transcribe y entra al historial.
6. ☑️ Activa la **multi-selección** del encabezado, marca varias capturas/textos y pulsa **PDF** o **ZIP** para subirlos de una vez como contexto a la IA.
7. `Esc` o clic fuera cierra el panel.

## ⚙️ Configuración

Abre **Preferencias** (`⌘,` desde el menú de Klip):

- **Atajos** — graba las combinaciones que prefieras (panel, voz y captura).
- **Transcripción de voz** — elige **proveedor** (OpenAI o Google Gemini), **modelo** e idioma.
- **OpenAI / Google Gemini** — pega la API key del proveedor que elegiste (solo se muestra esa sección). Se guarda en un archivo local `0600`.
- **Historial** — número máximo de elementos.
- **Privacidad** — ignorar contraseñas/contenido sensible, excluir apps.

## 🔐 Privacidad

- **Local primero**: tu historial vive en `~/Library/Application Support/Klip/` (`items.json` + `images/` + `audio/`). Nada sale de tu Mac salvo el audio que **tú** envías al proveedor de IA que elijas (OpenAI o Gemini) para transcribir.
- **Sin secretos en el repo**: las API keys se guardan en **archivos locales** (`openai.key`, `gemini.key`, permisos `0600`), jamás en el código ni en el repositorio.
- El **historial** (`items.json`), las **imágenes** y el **audio** de las notas de voz se guardan solo en tu Mac con permisos `0600` (carpetas `0700`). El enmascarado de credenciales es visual; el contenido vive localmente como el resto del historial.
- **Sin telemetría**.
- Klip **ignora** el contenido marcado como oculto por los gestores de contraseñas, y puedes **excluir** apps concretas.
- Los **tokens/API keys** que copies se detectan y se guardan **enmascarados** (filtro 🔑).

## 🏗️ Arquitectura

| Archivo | Responsabilidad |
|---|---|
| `main.swift` / `AppDelegate.swift` | Arranque, barra de menú, menú Editar, atajos globales. |
| `ClipboardManager.swift` | Monitoreo del portapapeles, historial, origen, privacidad, colecciones. |
| `ClipboardItem.swift` / `Storage.swift` | Modelo y persistencia (JSON + imágenes + audio + PDF/ZIP). |
| `PanelController.swift` / `HistoryView.swift` | Panel HUD y la interfaz (SwiftUI), multi-selección y exportación. |
| `SnapController.swift` / `ScreenCapturer.swift` | Flujo de captura nativa (ScreenCaptureKit). |
| `CaptureOverlayController.swift` | Overlay de selección de región (freeze-frame + badge). |
| `SnapEditorController.swift` / `AnnotationCanvasView.swift` / `AnnotationModel.swift` | Editor de anotación y modelo de anotaciones. |
| `HotKey.swift` / `Settings.swift` | Atajos (Carbon) y preferencias (UserDefaults). |
| `OCR.swift` | Extracción de texto con Vision. |
| `Recorder.swift` / `AudioPlayer.swift` | Grabación, transcripción en 2º plano y reproducción de notas de voz. |
| `OpenAIClient.swift` / `GeminiClient.swift` | Transcripción vía OpenAI o Google Gemini (proveedor y modelo seleccionables). |
| `SecretStore.swift` | API keys en archivos locales `0600` (`openai.key`, `gemini.key`). |
| `Paster.swift` / `LoginItem.swift` | Auto-pegado y arranque al inicio. |
| `Markdownify.swift` | Conversión y exportación a Markdown (local). |

## 🗺️ Hoja de ruta

**Por ahora Klip es solo para Mac.** Lo siguiente:

- [ ] **Versión para Windows** 🪟 — el gran próximo paso.
- [ ] Más acciones rápidas por tipo (correos, números).
- [ ] Traducir / resumir / limpiar texto con IA.
- [ ] Favoritos · sincronización opcional entre Macs.
- [ ] Firma con Developer ID + notarización para distribución sin avisos.

**Ya disponible:** historial texto+imágenes · captura + anotación nativa (Klip Snap) · OCR · notas de voz (OpenAI/Gemini con modelo configurable) con audio guardado y reintento · copiar como bloque de código · multi-selección + combinar en PDF/ZIP · colecciones · nombrar y buscar · abrir enlaces y muestra de color · Markdown · exportar/importar · firma estable.

## 🤝 Contribuir

¡Las contribuciones son bienvenidas! Abre un *issue* o un *pull request*. El proyecto compila solo con las Command Line Tools (sin Xcode), así que es fácil de arrancar.

## 👤 Autor

Creado y dirigido por **Martin Velasco O.** — [@tamibot](https://github.com/tamibot) · Proper.

## 📄 Licencia

[MIT](LICENSE) © 2026 Martin Velasco O. — úsalo, modifícalo y compártelo libremente.
