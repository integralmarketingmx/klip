import AppKit
import SwiftUI

/// Panel flotante que puede recibir el foco de teclado sin volverse ventana principal.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Controla la ventana emergente del historial: vibrancy HUD, posición contextual,
/// aparición animada, navegación por teclado, cierre al clic fuera, auto-pegado, voz y Markdown.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    var panel: KeyablePanel!                 // internal: usado por PanelController+Voice/Upload/Keyboard.swift
    private var effectView: NSVisualEffectView!
    let manager: ClipboardManager            // internal: usado por PanelController+Capture/Voice/Upload/Actions.swift
    let selection = SelectionModel()          // internal: usado por PanelController+Voice/Actions/Keyboard.swift
    let recorder = Recorder()                 // internal: usado por PanelController+Voice/Actions/Keyboard.swift
    private weak var statusItem: NSStatusItem?
    weak var previousApp: NSRunningApplication?   // internal: usado por PanelController+Voice/Actions.swift

    /// Lo inyecta AppDelegate para abrir Preferencias desde el panel (estado sin API key).
    var onOpenPreferences: (() -> Void)?

    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    /// Nº de paneles modales (guardar/abrir) activos. Mientras sea > 0 el panel no se cierra al perder
    /// el foco. Es un contador (no un bool) para que dos paneles solapados no se pisen el estado.
    var modalCount = 0                        // internal: usado por PanelController+Export/Voice/Actions.swift
    var isModalActive: Bool { modalCount > 0 }   // internal: usado por PanelController+Voice.swift
    /// Evita lanzar una segunda exportación (PDF/ZIP) mientras una está en curso.
    var exportInFlight = false                // internal: usado por PanelController+Export.swift
    var isRenaming = false                    // internal: usado por PanelController+Voice/Actions/Keyboard.swift
    /// true mientras corre `screencapture -i` (no auto-cerrar el panel por el clic de selección).
    var capturing = false                     // internal: usado por PanelController+Capture.swift
    private let cornerRadius: CGFloat = 12
    var recordingPanel: NSPanel?              // internal: usado por PanelController+Voice.swift
    var guideWindow: NSWindow?                // internal: usado por PanelController+Actions.swift
    var uploadWindow: NSWindow?               // internal: usado por PanelController+Actions.swift
    var annotationWindow: NSWindow?           // internal: usado por PanelController+Capture.swift
    /// Confirmación breve no-modal de subida; se auto-cierra a los pocos segundos.
    var uploadToastWindow: NSWindow?          // internal: usado por PanelController+Upload.swift
    /// Ventana del compositor de email; usada por PanelController+Email.swift.
    var emailWindow: NSWindow?

    init(manager: ClipboardManager, statusItem: NSStatusItem?) {
        self.manager = manager
        self.statusItem = statusItem
        super.init()
        buildPanel()
    }

    deinit {
        // El ciclo panel↔delegate es seguro (PanelController es singleton de la app), se limpia por defensa.
        panel?.delegate = nil
    }

    private func buildPanel() {
        recorder.onVoiceNoteStarted = { [weak self] fn, dur in self?.manager.beginVoiceNote(audioFileName: fn, duration: dur) }
        recorder.onVoiceNoteTranscribed = { [weak self] id, text in self?.manager.finishVoiceNote(id: id, text: text) }
        recorder.onVoiceNoteFailed = { [weak self] id, err in
            self?.manager.failVoiceNote(id: id, reason: err?.message)
            // Solo si fue problema de CLAVE ofrecemos pegar una nueva (panel A); red/otros no.
            if let err, err.isAuth { self?.presentTranscriptionKeyAlert(noteID: id, error: err) }
        }
        recorder.onVoiceNoteRetrying = { [weak self] id in self?.manager.markVoiceNoteTranscribing(id: id) }

        let root = HistoryView(
            manager: manager,
            selection: selection,
            recorder: recorder,
            onPick: { [weak self] item in self?.pick(item) },
            onSaveImage: { [weak self] item in self?.saveImage(item) },
            onAnnotate: { [weak self] item in self?.annotateExistingImage(item) },
            onUploadLink: { [weak self] item in await self?.uploadAndCopyLink(item) },
            onComposeEmail: { [weak self] item in self?.composeEmail(item) },
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
            guard let self, !self.isModalActive, !self.isRenaming, !self.recorder.isRecording,
                  !self.capturing, !Settings.shared.alwaysOnTop else { return }   // fijado: no auto-cerrar
            self.hide(restoreFocus: false)
        }
    }

    private func removeMonitors() {
        [keyMonitor, localClickMonitor, globalClickMonitor].forEach {
            if let m = $0 { NSEvent.removeMonitor(m) }
        }
        keyMonitor = nil; localClickMonitor = nil; globalClickMonitor = nil
    }

    // MARK: - Posicionamiento

    private func positionPanel() {
        let size = panel.frame.size
        let gap: CGFloat = 6
        if let btnWin = statusItem?.button?.window {
            let b = btnWin.frame
            let screen = btnWin.screen ?? NSScreen.main ?? NSScreen.screens.first!
            panel.setFrameOrigin(PanelPositioner.originBelowStatusButton(
                buttonFrame: b, size: size, gap: gap, visibleFrame: screen.visibleFrame))
        } else {
            let m = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(m) }
                ?? NSScreen.main ?? NSScreen.screens.first!
            panel.setFrameOrigin(PanelPositioner.originBelowMouse(
                mouseLocation: m, size: size, gap: gap, visibleFrame: screen.visibleFrame))
        }
    }

    func showAlert(_ title: String, _ info: String) {   // internal: usado por PanelController+Export/Voice/Upload/Actions.swift
        let a = NSAlert(); a.messageText = title; a.informativeText = info
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    // MARK: - NSWindowDelegate (respaldo de cierre al perder el foco)

    func windowDidResignKey(_ notification: Notification) {
        // Fijado (always on top) o capturando: no cerrar al perder el foco.
        guard !isModalActive, !isRenaming, !recorder.isRecording,
              !capturing, !Settings.shared.alwaysOnTop else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible, !self.isModalActive, !self.isRenaming,
                  !self.recorder.isRecording, !self.capturing, !Settings.shared.alwaysOnTop,
                  !self.panel.isKeyWindow else { return }
            self.hide(restoreFocus: false)
        }
    }
}
