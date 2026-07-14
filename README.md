<div align="center">

# 📋 Klip

**The clipboard manager for vibe coders — native to Mac.**
Everything you copy while building with AI — code, errors, screenshots, prompts and keys — one shortcut away.

Text & image history · **native capture + annotation** · **OCR** · **voice notes → text** (OpenAI or Gemini) · **copy as code block** · **bundle context into a PDF/ZIP** · credential manager. Lives in the menu bar: light, fast and private.

🆓 Free & open source (MIT) · 🔒 No telemetry · 🍎 Native Swift (no Electron)

<br/>

<img src="docs/klip-preview.gif" alt="Klip in action: snip an area of the screen, have it appear in Klip and pull its text with OCR; and record a voice note that transcribes itself" width="500"/>

<sub>Snip an area → it lands in Klip → pull the text (OCR) · and record a voice note that transcribes itself.</sub>

</div>

> ### 🖥️ For now, Mac only
> Klip is a **native macOS** app and requires **macOS 14 (Sonoma) or later** (Apple Silicon or Intel).
> A **Windows 🪟 version is planned**. Your data stays on your machine.

---

## 🤔 Why Klip if you code with AI?

"Vibe coding" is a constant back-and-forth of copy-paste between your editor and tools like Claude, ChatGPT or Cursor: code snippets, error messages, UI screenshots, terminal output, dictated prompts and API keys. Klip is built for that flow:

- **Never lose a snippet** — everything you copy lands in a searchable history.
- **Snip an error and annotate it** (arrows, text, highlighter) without leaving the keyboard, and it lands in Klip ready to paste into the AI.
- **Pull the text out of a screenshot** (OCR) to paste a log that was stuck in an image.
- **Copy as a code block** (` ``` `) to paste cleanly into a chat.
- **Dictate a prompt** and Klip transcribes it to text.
- **Bundle several clips** (screenshots + text) into a **PDF or ZIP** to upload as context in one shot.
- **Keep your API keys** detected and masked, named and searchable.

## ✨ Features

### 📋 Clipboard
- **Automatic history** of **text and images/screenshots**.
- **Instant search** with **match highlighting** + **keyboard navigation** (↑/↓, Enter, `⌘1`–`⌘9`, `Esc`).
- **Type filters** (text · images · voice · credentials · favorites); a type chip only shows up once you actually have items of that type.
- **Auto-paste** into the active app · **Favorite** ⭐ · **Delete** 🗑️ (with confirmation on clear-all).
- **Readable date** on every item: *"Tue, Jul 04 · 10:43"*, *"Today"*, *"Yesterday"*.

### 📸 Native capture + annotation (Klip Snap)
- Global shortcut **`⌘⇧U`** → snip a region of the screen (drag a selection over a dimmed *freeze-frame*, with a live dimension badge and correct Retina scale). Uses **ScreenCaptureKit** (not the deprecated API).
- Built-in **annotation editor**: pencil, line, **arrow**, rectangle, ellipse, highlighter, **editable/movable/resizable text**, color, stroke width and **undo**.
- When you're done, the annotated capture lands in **history** (ready for **OCR** and search) and on the clipboard.
- Also from the 📷 button in the panel or the menu-bar menu.

### 🖼️ Images
- Large preview (cached thumbnails for smooth scrolling), **open large** and **save to file**.
- **OCR** (extract text from an image) with Apple's **Vision** engine — free and on-device. Perfect for pulling the text out of a log or error you copied as a screenshot.

### 🎙️ Voice notes → text
- **Record** (`⌘⇧I`) or **upload a file** (m4a, mp3, wav, **WhatsApp .opus**, ogg, flac…).
- Transcribes **in the background** — you can record another one right away.
- **The original audio is kept** with **duration** and a **progress bar**: play it (▶) or reveal it in Finder, and **retry (↻)** if a transcription fails.

### 🤖 AI: you pick the engine
- **OpenAI** or **Google Gemini** for transcription. Bring your own key for either.
- For **Gemini** you can pick the model (`gemini-flash-latest`, `-flash-lite-latest`, `-pro-latest`, `2.5-flash`, `2.5-pro`); for **OpenAI**, `gpt-4o-mini-transcribe` or `whisper-1`.
- **Dictation language** is selectable (and auto-detect), so transcription is natural in your language.

### 🧰 Built for pasting into AI
- **Copy as code block** — wraps the text in ` ``` ` to paste cleanly into a chat.
- **Copy as Markdown** for a single item, or export the **whole history** to Markdown.
- **Save text as a file** (`.txt`/`.md`) to drag into a tool when the chat won't let you paste it.
- **Batch multi-select** (☑️ icon in the header): mark several clips and…
  - **Combine them into a PDF** (one page per screenshot/text) to upload a full context at once.
  - **Export them as a ZIP** (the chosen subset, separate from the backup ZIP).
  - **Assign them to a collection**.

### 🏷️ Organization
- **Collections** — group related clips (e.g. the context of one task) and filter them with a chip.
- **Name any item** and find it by that name (great for your credentials).
- **Type-aware actions**: **open links** 🔗 and a **color swatch** for hex values (`#1E90FF`).
- **Mini credential manager** 🔑: detects tokens and API keys when you copy them, stores them **masked** (👁 to reveal/copy), with their own filter. They are never auto-pasted (copied so you paste them by hand, for safety).

### 💾 Backup
- **Export / import** the whole history (images and audio included) as a `.zip`. **Never** includes your API keys.

### 🌍 Languages
- Interface available in **English, Spanish, French, German, Italian, Portuguese, Chinese (Simplified) and Japanese**, switchable in Preferences.

### 🔒 Privacy & system
- All **local** with `0600` permissions · **no telemetry** · ignores passwords and lets you **exclude apps**.
- **Stable signing**: macOS asks for permissions (microphone, screen recording…) **once** and remembers them across updates.
- **Launch at login** optional.

## ⌨️ Shortcuts

| Shortcut | Action |
|---|---|
| `⌘⇧E` | Open the history panel |
| `⌘⇧I` | Record / stop a voice note |
| `⌘⇧U` | **Capture and annotate** a region (Klip Snap) |
| `↑` / `↓` · `Enter` | Navigate and pick an item |
| `⌘1`–`⌘9` | Pick (and paste) item #1–9 |
| `Esc` | Close the panel |
| `⌘⇧⌃4` | *(macOS)* screenshot to clipboard → also lands in Klip |

> All three global shortcuts (`⌘⇧E`, `⌘⇧I`, `⌘⇧U`) are **configurable** in Preferences › Shortcuts.
> A **letter** (`U`) is used instead of a number: `⌘⇧2` was hijacked by other apps (e.g. Loom), and `⌘⇧3`/`4`/`5` are the system screenshots.

## 🧰 Requirements

- **macOS 14 (Sonoma) or later** — tested on macOS 26, Apple Silicon.
- **Xcode Command Line Tools** (no full Xcode needed):
  ```bash
  xcode-select --install
  ```
- *(Optional)* An **OpenAI or Google Gemini API key** for voice notes. It's stored in a **local file**, never in the code or the repository.

## ⚡ Quick install

```bash
git clone https://github.com/tamibot/klip.git klip
cd klip
./install.sh
```

That builds Klip, signs it, copies it to `/Applications`, launches it and registers launch-at-login.
You'll see the 📋 icon in the menu bar. Press **`⌘⇧E`** to open the history.

> On first run, `install.sh` creates a **local signing certificate** (`Klip Code Signing`) in your Keychain so the signature is stable. That way macOS asks for permissions (microphone, accessibility, screen recording) **once** and remembers them across updates, instead of re-prompting on every reinstall. It's local and reversible (you can delete it from *Keychain Access*).
>
> macOS may ask you to approve the "login item" in *Settings › General*. For **auto-paste**, grant Accessibility when prompted (Klip menu → *Enable auto-paste…*). The first capture with `⌘⇧U` will ask for **Screen Recording**.

### Build without installing

```bash
./build.sh        # produces Klip.app in the project folder
open Klip.app
```

### Development

```bash
swift build       # debug build
swift run Klip    # run directly
```

## 🚀 Usage (a vibe coder's typical flow)

1. **Copy anything** while you code (code, terminal output, an error message). It all lands in Klip.
2. **`⌘⇧E`** → open the panel. Type to **search**; use **↑/↓ + Enter** or **click** to pick an item (it auto-pastes if you enabled auto-paste).
3. To paste code into an AI chat, hover the row and hit **`</>`** (*copy as code block*).
4. **`⌘⇧U`** → snip the error/UI from the screen, annotate it (arrow + text) and it lands in Klip. Hover and hit **OCR** if you want its text.
5. 🎙️ **`⌘⇧I`** to dictate a prompt; on stop, it transcribes and lands in the history.
6. ☑️ Turn on **multi-select** in the header, mark several screenshots/texts and hit **PDF** or **ZIP** to upload them as context to the AI in one go.
7. `Esc` or a click outside closes the panel.

## ⚙️ Configuration

Open **Preferences** (`⌘,` from the Klip menu):

- **Shortcuts** — record the combinations you prefer (panel, voice and capture).
- **Voice transcription** — pick the **provider** (OpenAI or Google Gemini), **model** and language.
- **OpenAI / Google Gemini** — paste the API key for the provider you chose (only that section shows). Stored in a local `0600` file.
- **History** — maximum number of items.
- **Privacy** — ignore passwords/sensitive content, exclude apps.
- **Language** — interface language.

## 🔐 Privacy

- **Local-first**: your history lives in `~/Library/Application Support/Klip/` (`items.json` + `images/` + `audio/`). Nothing leaves your Mac except the audio **you** send to the AI provider you choose (OpenAI or Gemini) to transcribe.
- **No secrets in the repo**: API keys are stored in **local files** (`openai.key`, `gemini.key`, `0600` permissions), never in the code or the repository.
- The **history** (`items.json`), **images** and voice-note **audio** are stored only on your Mac with `0600` permissions (`0700` folders). Credential masking is visual; the content lives locally like the rest of the history.
- **No telemetry**.
- Klip **ignores** content marked as concealed by password managers, and you can **exclude** specific apps.
- **Tokens/API keys** you copy are detected and stored **masked** (🔑 filter).

## 🏗️ Architecture

| File | Responsibility |
|---|---|
| `main.swift` / `AppDelegate.swift` | Startup, menu bar, Edit menu, global shortcuts. |
| `ClipboardManager.swift` | Clipboard monitoring, history, source, privacy, collections. |
| `ClipboardItem.swift` / `Storage.swift` | Model and persistence (JSON + images + audio + PDF/ZIP). |
| `PanelController.swift` / `HistoryView.swift` | HUD panel and the UI (SwiftUI), multi-select and export. |
| `SnapController.swift` / `ScreenCapturer.swift` | Native capture flow (ScreenCaptureKit). |
| `CaptureOverlayController.swift` | Region-selection overlay (freeze-frame + badge). |
| `SnapEditorController.swift` / `AnnotationCanvasView.swift` / `AnnotationModel.swift` | Annotation editor and annotation model. |
| `HotKey.swift` / `Settings.swift` | Shortcuts (Carbon) and preferences (UserDefaults). |
| `OCR.swift` | Text extraction with Vision. |
| `Recorder.swift` / `AudioPlayer.swift` | Recording, background transcription and voice-note playback. |
| `OpenAIClient.swift` / `GeminiClient.swift` | Transcription via OpenAI or Google Gemini (selectable provider and model). |
| `L10n.swift` | Lightweight localization (8 languages). |
| `SecretStore.swift` | API keys in local `0600` files (`openai.key`, `gemini.key`). |
| `Paster.swift` / `LoginItem.swift` | Auto-paste and launch-at-login. |
| `Markdownify.swift` | Markdown conversion and export (local). |

## 🗺️ Roadmap

**Klip is Mac-only for now.** Next up:

- [ ] **Windows version** 🪟 — the big next step.
- [ ] More type-aware quick actions (emails, numbers).
- [ ] Translate / summarize / clean up text with AI.
- [ ] Favorites sync · optional sync between Macs.
- [ ] Developer ID signing + notarization for warning-free distribution.

**Already available:** text+image history · native capture + annotation (Klip Snap) · OCR · voice notes (OpenAI/Gemini with selectable model) with saved audio and retry · copy as code block · multi-select + combine into PDF/ZIP · collections · name and search · open links and color swatch · Markdown · export/import · stable signing · 8 UI languages.

## 🤝 Contributing

Contributions are welcome! Open an *issue* or a *pull request*. The project builds with just the Command Line Tools (no Xcode), so it's easy to get started. Code and comments are in English to keep the project approachable for everyone.

## 👤 Author

Created and maintained by **Martin Velasco O.** — [@tamibot](https://github.com/tamibot).

## 📄 License

[MIT](LICENSE) © 2026 Martin Velasco O. — use it, modify it and share it freely.
