import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Grabación de voz + subida/transcripción de audio
extension PanelController {

    /// Atajo global de voz: abre el popup dedicado de grabación y alterna grabar/detener.
    func toggleVoiceRecording() {
        MainActor.assumeIsolated {
            if recorder.state == .recording { recorder.stop(); return }
            guard !recorder.isRecording else { return }
            if recordingPanel?.isVisible != true {   // al re-grabar con el popup abierto, conservar la app original
                previousApp = NSWorkspace.shared.frontmostApplication
            }
            showRecordingPopup()
            recorder.start()
        }
    }

    private func showRecordingPopup() {
        if recordingPanel == nil {
            let view = RecordingView(
                recorder: recorder,
                onStop: { [weak self] in MainActor.assumeIsolated { self?.recorder.stop() } },
                onCancel: { [weak self] in MainActor.assumeIsolated { self?.recorder.cancel() } },
                onClose: { [weak self] in self?.closeRecordingPopup() },
                onOpenPreferences: { [weak self] in self?.onOpenPreferences?() }
            )
            let p = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.level = .floating; p.isReleasedWhenClosed = false
            p.isMovableByWindowBackground = true   // arrastrable desde el fondo (panel borderless sin barra de título)
            p.hidesOnDeactivate = false   // no ocultarse al volver el foco a la app del usuario
            let fx = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 360, height: 320))
            fx.material = .hudWindow; fx.blendingMode = .behindWindow; fx.state = .active
            fx.wantsLayer = true; fx.layer?.cornerRadius = 16; fx.layer?.masksToBounds = true
            fx.autoresizingMask = [.width, .height]
            let host = NSHostingView(rootView: view)
            host.frame = fx.bounds; host.autoresizingMask = [.width, .height]; fx.addSubview(host)
            p.contentView = fx
            recordingPanel = p
        }
        if let screen = NSScreen.main, let p = recordingPanel {
            let vf = screen.visibleFrame; let s = p.frame.size
            p.setFrameOrigin(NSPoint(x: vf.midX - s.width / 2, y: vf.midY + 120))
        }
        NSApp.activate(ignoringOtherApps: true)
        recordingPanel?.makeKeyAndOrderFront(nil)
    }

    private func closeRecordingPopup() {
        recordingPanel?.orderOut(nil)
        previousApp?.activate()   // la transcripción corre en 2º plano; solo devolvemos el foco
    }

    func uploadAudio() {
        // El recorder.state es compartido; limpia un .error/.missingAPIKey previo para mostrar la dropzone.
        if recorder.state != .recording { recorder.reset() }
        showUploadWindow()
    }

    private func showUploadWindow() {
        if uploadWindow == nil {
            let view = UploadView(
                recorder: recorder,
                onChoose: { [weak self] in self?.chooseAudioFiles() },
                onFiles: { [weak self] urls in MainActor.assumeIsolated { self?.submitAudioFiles(urls) } },
                onClose: { [weak self] in self?.uploadWindow?.orderOut(nil) },
                onOpenPreferences: { [weak self] in self?.onOpenPreferences?() }
            )
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Subir audio"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: view)
            w.center()
            uploadWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        uploadWindow?.makeKeyAndOrderFront(nil)
    }

    private func chooseAudioFiles() {
        let p = NSOpenPanel()
        var types: [UTType] = [.audio]
        for ext in ["opus", "oga"] {   // .opus de WhatsApp no siempre conforma a public.audio
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        p.allowedContentTypes = types
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        p.begin { [weak self] resp in
            guard resp == .OK, !p.urls.isEmpty else { return }
            MainActor.assumeIsolated { self?.submitAudioFiles(p.urls) }
        }
    }

    /// Manda los audios a transcribir (en 2º plano). La ventana queda abierta mostrando el progreso
    /// ("Transcribiendo N…"); el usuario la cierra cuando quiera (las notas aparecen en el historial).
    @MainActor
    private func submitAudioFiles(_ urls: [URL]) {
        recorder.transcribeFiles(urls)
    }

    /// Panel A: la transcripción falló por una CLAVE inválida. Permite pegar una clave nueva
    /// ahí mismo (se guarda como preferencia) y reintentar, o usar OpenAI esta vez, o cerrar.
    func presentTranscriptionKeyAlert(noteID: UUID, error: TranscriptionError) {
        guard !isModalActive else { return }   // no apilar sobre otro modal
        let providerKey: SecretStore.Key = error.provider == "gemini" ? .gemini : .openai
        let other = AIProvider.other(of: error.provider)            // proveedor de respaldo
        let otherName = other == "gemini" ? "Gemini" : "OpenAI"
        let audioFileName = manager.items.first(where: { $0.id == noteID })?.audioFileName

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "No se pudo transcribir la nota de voz"
        alert.informativeText = "\(error.message)\n\nTu nota está guardada. Pega una clave válida y reintenta."

        // Campo para la clave nueva.
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = error.provider == "gemini" ? "AIza…" : "sk-…"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let save = alert.addButton(withTitle: "Guardar y reintentar")  // .alertFirstButtonReturn (default)
        save.keyEquivalent = "\r"
        let canUseOther = AIProvider.hasKey(for: other) && audioFileName != nil
        if canUseOther { alert.addButton(withTitle: "Usar \(otherName) esta vez") } // .alertSecondButtonReturn
        let close = alert.addButton(withTitle: "OK")                           // tercer (o segundo) botón
        close.keyEquivalent = "\u{1b}"

        modalCount += 1
        isRenaming = true   // bloquea el auto-cierre del panel mientras el modal está abierto
        NSApp.activate(ignoringOtherApps: true)
        let resp = alert.runModal()
        isRenaming = false
        modalCount -= 1

        switch resp {
        case .alertFirstButtonReturn:   // Guardar y reintentar
            let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            let ok = (try? SecretStore.set(key, providerKey)) ?? false
            guard ok else { showAlert("No se pudo guardar la clave", "Revisa permisos de la carpeta de Klip."); return }
            if let af = audioFileName {
                MainActor.assumeIsolated { recorder.retry(itemID: noteID, audioFileName: af) }
            }
        case .alertSecondButtonReturn where canUseOther:   // Usar el otro proveedor esta vez
            if let af = audioFileName {
                MainActor.assumeIsolated { recorder.retry(itemID: noteID, audioFileName: af, forceProvider: other) }
            }
        default:
            break   // OK / cerrar: la nota queda fallida con su audio para reintentar luego
        }
        if panel.isVisible { panel.makeKeyAndOrderFront(nil); selection.focusToken &+= 1 }
    }
}
