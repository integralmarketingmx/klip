import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Panel flotante que puede recibir el foco de teclado sin volverse ventana principal.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Controla la ventana emergente del historial: vibrancy HUD, posición contextual,
/// aparición animada, navegación por teclado, cierre al clic fuera, auto-pegado, voz y Markdown.
final class PanelController: NSObject, NSWindowDelegate {
    private var panel: KeyablePanel!
    private var effectView: NSVisualEffectView!
    private let manager: ClipboardManager
    private let selection = SelectionModel()
    private let recorder = Recorder()
    private weak var statusItem: NSStatusItem?
    private weak var previousApp: NSRunningApplication?

    /// Lo inyecta AppDelegate para abrir Preferencias desde el panel (estado sin API key).
    var onOpenPreferences: (() -> Void)?

    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    /// Nº de paneles modales (guardar/abrir) activos. Mientras sea > 0 el panel no se cierra al perder
    /// el foco. Es un contador (no un bool) para que dos paneles solapados no se pisen el estado.
    private var modalCount = 0
    private var isModalActive: Bool { modalCount > 0 }
    /// Evita lanzar una segunda exportación (PDF/ZIP) mientras una está en curso.
    private var exportInFlight = false
    private var isRenaming = false
    private let cornerRadius: CGFloat = 12
    private var recordingPanel: NSPanel?
    private var guideWindow: NSWindow?
    private var uploadWindow: NSWindow?
    private var annotationWindow: NSWindow?

    init(manager: ClipboardManager, statusItem: NSStatusItem?) {
        self.manager = manager
        self.statusItem = statusItem
        super.init()
        buildPanel()
    }

    private func buildPanel() {
        recorder.onVoiceNoteStarted = { [weak self] fn, dur in self?.manager.beginVoiceNote(audioFileName: fn, duration: dur) }
        recorder.onVoiceNoteTranscribed = { [weak self] id, text in self?.manager.finishVoiceNote(id: id, text: text) }
        recorder.onVoiceNoteFailed = { [weak self] id in self?.manager.failVoiceNote(id: id) }
        recorder.onVoiceNoteRetrying = { [weak self] id in self?.manager.markVoiceNoteTranscribing(id: id) }

        let root = HistoryView(
            manager: manager,
            selection: selection,
            recorder: recorder,
            onPick: { [weak self] item in self?.pick(item) },
            onSaveImage: { [weak self] item in self?.saveImage(item) },
            onCopyMarkdown: { [weak self] item in self?.copyMarkdown(of: item) },
            onCopyAllMarkdown: { [weak self] in self?.copyAllMarkdown() },
            onOpenPreferences: { [weak self] in self?.hide(restoreFocus: false); self?.onOpenPreferences?() },
            onUploadAudio: { [weak self] in self?.uploadAudio() },
            onVoiceRecord: { [weak self] in self?.toggleVoiceRecording() },
            onShowGuide: { [weak self] in self?.showGuide() },
            onRename: { [weak self] item in self?.renameItem(item) },
            onRetryTranscription: { [weak self] item in self?.retryTranscription(item) },
            onSaveAsFile: { [weak self] item in self?.saveTextAsFile(item) },
            onCopyAsCode: { [weak self] item in self?.copyAsCode(of: item) },
            onCaptureAnnotate: { [weak self] in self?.captureAndAnnotate(fullScreen: false) },
            onCombinePDF: { [weak self] items in self?.combineSelectedToPDF(items) },
            onExportZip: { [weak self] items in self?.exportSelectedZip(items) },
            onAssignCollection: { [weak self] items in self?.assignSelectedToCollection(items) }
        )

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        let fx = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 480, height: 640))
        fx.material = .menu
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = cornerRadius
        fx.layer?.masksToBounds = true
        fx.autoresizingMask = [.width, .height]
        self.effectView = fx

        let hosting = NSHostingView(rootView: root)
        hosting.frame = fx.bounds
        hosting.autoresizingMask = [.width, .height]
        fx.addSubview(hosting)

        panel.contentView = fx
        self.panel = panel
    }

    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        guard !panel.isVisible else { return }   // idempotente: evita reinstalar monitores
        previousApp = NSWorkspace.shared.frontmostApplication
        positionPanel()

        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        selection.reset()
        selection.openToken &+= 1                 // dispara reseteo de búsqueda/foco en la vista
        if recordingPanel?.isVisible != true { recorder.reset() }  // no cerrar el popup de voz si está abierto

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.13
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        installMonitors()
    }

    func hide(restoreFocus: Bool = true) {
        removeMonitors()
        AudioPlayer.shared.stop()   // no dejar audio sonando al cerrar el panel
        panel.orderOut(nil)
        if restoreFocus { previousApp?.activate() }
    }

    // MARK: - Monitores (teclado + clic fuera)

    private func installMonitors() {
        removeMonitors()   // nunca dejar monitores huérfanos
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { e in e }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.isModalActive, !self.isRenaming, !self.recorder.isRecording else { return }
            self.hide(restoreFocus: false)
        }
    }

    private func removeMonitors() {
        [keyMonitor, localClickMonitor, globalClickMonitor].forEach {
            if let m = $0 { NSEvent.removeMonitor(m) }
        }
        keyMonitor = nil; localClickMonitor = nil; globalClickMonitor = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if isRenaming { return event }   // el diálogo de renombrar maneja sus propias teclas
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == 53 {   // Esc (el monitor siempre corre en el hilo principal)
            if recorder.state == .recording {
                MainActor.assumeIsolated { recorder.cancel() }   // aborta la grabación, no cierra
            } else if !recorder.isRecording {
                hide(restoreFocus: true)                         // no cerrar mientras transcribe
            }
            return nil
        }

        // En modo multi-selección por lote, el teclado NO pega/cierra (rompería el lote en curso): solo
        // navega con flechas; ⌘1-9 / Return no hacen pick. El ratón sigue marcando (onToggleCheck).
        if selection.selecting {
            switch event.keyCode {
            case 125: selection.moveDown(); return nil   // ↓
            case 126: selection.moveUp();   return nil   // ↑
            default:  return event                       // deja escribir en la búsqueda
            }
        }

        // ⌘1..⌘9 → selección rápida + pegar (solo si existe ese índice).
        if flags.contains(.command),
           let ch = event.charactersIgnoringModifiers,
           let n = Int(ch), (1...9).contains(n) {
            if n <= selection.visibleCount { selection.selectQuick(n); pickSelected() }
            return nil
        }
        if flags.contains(.command) { return event }   // no romper ⌘A/⌘C/⌘V en la búsqueda

        switch event.keyCode {
        case 125: selection.moveDown(); return nil    // ↓
        case 126: selection.moveUp();   return nil    // ↑
        case 36, 76: pickSelected();    return nil    // Return / Enter
        default: return event
        }
    }

    // MARK: - Posicionamiento

    private func positionPanel() {
        let size = panel.frame.size
        let gap: CGFloat = 6
        if let btnWin = statusItem?.button?.window {
            let b = btnWin.frame
            let screen = btnWin.screen ?? NSScreen.main ?? NSScreen.screens.first!
            panel.setFrameOrigin(clamp(x: b.midX - size.width / 2,
                                       y: b.minY - gap - size.height, size: size, into: screen.visibleFrame))
        } else {
            let m = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(m) }
                ?? NSScreen.main ?? NSScreen.screens.first!
            panel.setFrameOrigin(clamp(x: m.x - size.width / 2,
                                       y: m.y - size.height - gap, size: size, into: screen.visibleFrame))
        }
    }

    private func clamp(x: CGFloat, y: CGFloat, size: NSSize, into vf: NSRect) -> NSPoint {
        let hiX = max(vf.minX + 8, vf.maxX - size.width - 8)   // garantiza lo <= hi en pantallas pequeñas
        let hiY = max(vf.minY + 8, vf.maxY - size.height - 8)
        let cx = min(max(x, vf.minX + 8), hiX)
        let cy = min(max(y, vf.minY + 8), hiY)
        return NSPoint(x: cx, y: cy)
    }

    // MARK: - Acciones

    private func pick(_ item: ClipboardItem) {
        // Nota de voz sin transcripción: no hay texto que pegar → reproducir el audio y dejar el panel abierto.
        if item.kind == .text, (item.text?.isEmpty ?? true) {
            if let af = item.audioFileName { AudioPlayer.shared.toggle(fileName: af) }
            return
        }
        manager.copyToPasteboard(item)
        let target = previousApp
        hide(restoreFocus: false)
        if item.isCredential == true { target?.activate() }   // no auto-pegar secretos: solo copiar + devolver foco
        else { pasteOrRestore(target) }
    }

    private func pickSelected() {
        guard let id = selection.selectedID,
              let item = manager.items.first(where: { $0.id == id }) else { return }
        pick(item)
    }

    /// Pega automáticamente en la app previa (si hay permiso y app destino), o solo restaura el foco.
    private func pasteOrRestore(_ target: NSRunningApplication?) {
        guard let target, !target.isTerminated else { return }   // sin destino: solo queda copiado
        if Settings.shared.autoPaste { Paster.paste(into: target) }
        else { target.activate() }
    }

    private func copyMarkdown(of item: ClipboardItem) {
        let md = Markdownify.fromText(item.text ?? "")
        let target = previousApp
        manager.setClipboardText(md)
        hide(restoreFocus: false)
        pasteOrRestore(target)
    }

    private func copyAllMarkdown() {
        let md = MarkdownExporter.history(manager.items)
        let target = previousApp
        manager.setClipboardText(md)
        hide(restoreFocus: false)
        pasteOrRestore(target)
    }

    /// Copia el texto envuelto en un bloque de código Markdown (``` ```), listo para pegar en un chat de IA.
    private func copyAsCode(of item: ClipboardItem) {
        guard let t = item.text, !t.isEmpty else { return }
        let target = previousApp
        manager.setClipboardText("```\n\(t)\n```")
        hide(restoreFocus: false)
        pasteOrRestore(target)
    }

    /// Guarda el texto del elemento como archivo (.txt/.md) para arrastrarlo a una herramienta de IA
    /// cuando el chat no acepta pegarlo (textos/logs muy grandes).
    private func saveTextAsFile(_ item: ClipboardItem) {
        guard let t = item.text, !t.isEmpty else { return }
        let sp = NSSavePanel()
        var types: [UTType] = [.plainText]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        sp.allowedContentTypes = types
        sp.nameFieldStringValue = (item.name?.isEmpty == false ? item.name! : "klip-texto") + ".txt"
        sp.canCreateDirectories = true
        modalCount += 1   // guard de "hay un panel modal abierto" (no cerrar el panel detrás)
        NSApp.activate(ignoringOtherApps: true)
        sp.begin { [weak self] resp in
            if resp == .OK, let url = sp.url { try? t.data(using: .utf8)?.write(to: url, options: .atomic) }
            self?.modalCount -= 1
        }
    }

    // MARK: - Captura + anotación (vibe coders)

    /// Captura una zona (selector nativo) o la pantalla completa y abre el editor de anotación.
    func captureAndAnnotate(fullScreen: Bool) {
        hide(restoreFocus: false)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("klipcap-\(UUID().uuidString).png")
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = fullScreen ? ["-m", tmp.path] : ["-i", "-o", tmp.path]
            try? p.run(); p.waitUntilExit()
            let img = (try? Data(contentsOf: tmp)).flatMap { NSImage(data: $0) }   // carga completa antes de borrar
            try? FileManager.default.removeItem(at: tmp)
            DispatchQueue.main.async {
                guard let img else { return }   // el usuario canceló o faltó permiso de grabación de pantalla
                self.showAnnotationWindow(image: img)
            }
        }
    }

    private func showAnnotationWindow(image: NSImage) {
        let view = AnnotationView(
            image: image,
            onAddToKlip: { [weak self] img in self?.manager.addCapturedImage(img) },
            onClose: { [weak self] in self?.annotationWindow?.close() })
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0,
                                width: min(960, image.size.width + 40),
                                height: min(720, image.size.height + 96)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Anotar captura"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.center()
        annotationWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    // MARK: - Combinar / exportar selección

    func combineSelectedToPDF(_ items: [ClipboardItem]) {
        guard !items.isEmpty, !exportInFlight else { return }   // no solapar exportaciones
        exportInFlight = true
        modalCount += 1   // protege el panel durante toda la generación + guardado (cierra el hueco de carrera)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Storage.shared.combinedPDF(from: items)
            DispatchQueue.main.async {
                guard let result else {   // nada exportable: avisar en vez de "el botón no hace nada"
                    self.modalCount -= 1; self.exportInFlight = false
                    self.showAlert(L10n.t("export.empty.title"), L10n.t("export.empty.info"))
                    return
                }
                let sp = NSSavePanel()
                sp.allowedContentTypes = [.pdf]
                sp.nameFieldStringValue = "klip.pdf"
                sp.canCreateDirectories = true
                if result.exported < items.count {
                    sp.message = String(format: L10n.t("export.partial"), result.exported, items.count)
                }
                NSApp.activate(ignoringOtherApps: true)
                sp.begin { resp in
                    if resp == .OK, let url = sp.url { try? result.data.write(to: url, options: .atomic) }
                    self.modalCount -= 1; self.exportInFlight = false
                }
            }
        }
    }

    func exportSelectedZip(_ items: [ClipboardItem]) {
        guard !items.isEmpty, !exportInFlight else { return }
        let exportable = Storage.shared.zipExportableCount(items)
        guard exportable > 0 else { showAlert(L10n.t("export.empty.title"), L10n.t("export.empty.info")); return }
        exportInFlight = true
        let sp = NSSavePanel()
        sp.allowedContentTypes = [.zip]
        sp.nameFieldStringValue = "klip-seleccion.zip"
        sp.canCreateDirectories = true
        if exportable < items.count {
            sp.message = String(format: L10n.t("export.partial"), exportable, items.count)
        }
        modalCount += 1
        NSApp.activate(ignoringOtherApps: true)
        sp.begin { [weak self] resp in
            guard let self else { return }
            self.modalCount -= 1
            guard resp == .OK, let url = sp.url else { self.exportInFlight = false; return }
            DispatchQueue.global(qos: .userInitiated).async {
                try? Storage.shared.exportItemsZip(items, to: url)
                DispatchQueue.main.async { self.exportInFlight = false }
            }
        }
    }

    private func showAlert(_ title: String, _ info: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = info
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    func assignSelectedToCollection(_ items: [ClipboardItem]) {
        guard !items.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Añadir a colección"
        alert.informativeText = "Nombre de la colección (déjalo vacío para quitar de su colección)."
        alert.addButton(withTitle: "Aceptar")
        let cancel = alert.addButton(withTitle: L10n.t("common.cancel")); cancel.keyEquivalent = "\u{1b}"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        // Precargar solo si TODOS comparten la misma colección; si difieren, dejar vacío (no sobreescribir
        // con una colección arbitraria del lote heterogéneo).
        let current = Set(items.map { $0.collection ?? "" })
        field.stringValue = current.count == 1 ? (current.first ?? "") : ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        isRenaming = true
        NSApp.activate(ignoringOtherApps: true)
        let resp = alert.runModal()
        isRenaming = false
        if resp == .alertFirstButtonReturn {
            manager.assignCollection(Set(items.map { $0.id }), to: field.stringValue)
        }
        if panel.isVisible { panel.makeKeyAndOrderFront(nil); selection.focusToken &+= 1 }
    }

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

    func showGuide() {
        if guideWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Guía de Klip"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: GuideView())
            w.center()
            guideWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        guideWindow?.makeKeyAndOrderFront(nil)
    }

    private func uploadAudio() {
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

    /// Reintenta transcribir una nota de voz fallida (usa su audio guardado).
    private func retryTranscription(_ item: ClipboardItem) {
        guard let af = item.audioFileName, Storage.shared.audioExists(fileName: af) else { return }
        // Evita un segundo reintento (doble-clic) mientras ya está en curso → no duplica la llamada a la API.
        guard manager.items.first(where: { $0.id == item.id })?.preview != ClipboardManager.voiceTranscribing else { return }
        guard AIProvider.hasKey else { onOpenPreferences?(); return }   // sin clave: ofrecer configurarla
        MainActor.assumeIsolated { recorder.retry(itemID: item.id, audioFileName: af) }
    }

    /// Diálogo para ponerle (o cambiarle) el nombre a cualquier elemento. Buscable después.
    private func renameItem(_ item: ClipboardItem) {
        let alert = NSAlert()
        alert.messageText = L10n.t("rename.title")
        alert.informativeText = L10n.t("rename.info")
        alert.addButton(withTitle: L10n.t("rename.save"))
        let cancel = alert.addButton(withTitle: L10n.t("common.cancel"))
        cancel.keyEquivalent = "\u{1b}"   // Esc cancela (no se asigna solo en español)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = item.name ?? ""
        field.placeholderString = L10n.t("rename.placeholder")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        isRenaming = true
        NSApp.activate(ignoringOtherApps: true)
        let resp = alert.runModal()
        isRenaming = false
        if resp == .alertFirstButtonReturn { manager.rename(item, to: field.stringValue) }
        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            selection.focusToken &+= 1   // devolver el foco al buscador (sin limpiar búsqueda/filtro)
        }
    }

    private func saveImage(_ item: ClipboardItem) {
        guard item.kind == .image, let fn = item.imageFileName,
              let img = Storage.shared.loadImage(fileName: fn),
              let png = Storage.shared.pngData(from: img) else { return }
        let sp = NSSavePanel()
        sp.allowedContentTypes = [.png]
        sp.nameFieldStringValue = "captura.png"
        sp.canCreateDirectories = true
        modalCount += 1
        NSApp.activate(ignoringOtherApps: true)
        sp.begin { [weak self] resp in
            if resp == .OK, let url = sp.url { try? png.write(to: url, options: .atomic) }
            self?.modalCount -= 1
        }
    }

    // MARK: - NSWindowDelegate (respaldo de cierre al perder el foco)

    func windowDidResignKey(_ notification: Notification) {
        guard !isModalActive, !isRenaming, !recorder.isRecording else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible, !self.isModalActive, !self.isRenaming,
                  !self.recorder.isRecording, !self.panel.isKeyWindow else { return }
            self.hide(restoreFocus: false)
        }
    }
}
