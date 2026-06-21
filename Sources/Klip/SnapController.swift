import AppKit

/// Orquesta el flujo de captura "Klip Snap": permiso → captura del display bajo el cursor →
/// overlay de selección → editor de anotaciones → historial de Klip.
final class SnapController {
    private let manager: ClipboardManager
    private var overlay: CaptureOverlayController?
    private var editor: SnapEditorController?
    private var preview: CapturePreviewController?
    private var inProgress = false

    /// Se invoca tras añadir una captura al historial (para revelar el panel: el item "vuela" a Klip).
    var onCaptured: (() -> Void)?
    /// Lo inyecta AppDelegate: enviar por email la captura anotada desde el editor (abre el compositor).
    var onRequestEmail: ((NSImage) -> Void)?

    init(manager: ClipboardManager) {
        self.manager = manager
        ScreenCapturer.warmUp()
    }

    /// Punto de entrada (atajo o menú).
    func start() {
        guard !inProgress else { return }

        guard ScreenCapturer.hasPermission() else {
            promptForPermission()
            return
        }

        inProgress = true
        let mouse = NSEvent.mouseLocation
        Task { @MainActor in
            do {
                let shot = try await ScreenCapturer.captureDisplay(containing: mouse)
                self.inProgress = false
                self.presentOverlay(shot)
            } catch CaptureError.noPermission {
                self.inProgress = false          // liberar ANTES del modal (evita reentrancia del runloop)
                self.promptForPermission()
            } catch {
                self.inProgress = false
                NSSound.beep()
            }
        }
    }

    /// Captura de PANTALLA COMPLETA: captura el display bajo el cursor y abre el editor directamente,
    /// SIN el overlay de selección de región (re-portado del menú "Pantalla completa" pre-Snap).
    func startFullScreen() {
        guard !inProgress else { return }
        guard ScreenCapturer.hasPermission() else { promptForPermission(); return }

        inProgress = true
        let mouse = NSEvent.mouseLocation
        Task { @MainActor in
            do {
                let shot = try await ScreenCapturer.captureDisplay(containing: mouse)
                self.inProgress = false
                let image = NSImage(cgImage: shot.cgImage, size: shot.screen.frame.size)
                self.openEditor(with: image)
            } catch CaptureError.noPermission {
                self.inProgress = false
                self.promptForPermission()
            } catch {
                self.inProgress = false
                NSSound.beep()
            }
        }
    }

    @MainActor
    private func presentOverlay(_ shot: DisplayShot) {
        let overlay = CaptureOverlayController(shot: shot) { [weak self] image in
            self?.overlay = nil
            guard let self, let image else { return }
            self.presentPreview(image)
        }
        self.overlay = overlay
        overlay.present()
    }

    /// Miniatura flotante tras seleccionar la región: clic → editar; ignorar (~6 s) → solo guardar en
    /// Klip. La imagen se copia al portapapeles de inmediato (la miniatura muestra "✓ Copiado").
    @MainActor
    private func presentPreview(_ image: NSImage) {
        manager.copyCapturedToClipboard(image)
        let preview = CapturePreviewController(
            image: image,
            onEdit: { [weak self] img in
                self?.preview = nil
                self?.openEditor(with: img)
            },
            onSaveOnly: { [weak self] img in
                self?.preview = nil
                guard let self else { return }
                _ = self.manager.addAnnotatedScreenshot(img, copyToClipboard: false)   // ya copiada
                self.onCaptured?()
            })
        self.preview = preview
        preview.show()
    }

    @MainActor
    private func openEditor(with image: NSImage) {
        let editor = SnapEditorController(image: image) { [weak self] result in
            self?.editor = nil
            guard let self, let result else { return }   // nil = cerrado sin guardar
            self.manager.addAnnotatedScreenshot(result, copyToClipboard: true)
            self.onCaptured?()
        }
        if let onRequestEmail { editor.onSendEmail = onRequestEmail }
        self.editor = editor
        editor.present()
    }

    /// Sin permiso de Grabación de pantalla. La PRIMERA vez dejamos solo el prompt nativo del sistema
    /// (`requestPermission`); en intentos posteriores (cuando el prompt nativo ya no reaparece) mostramos
    /// nuestra guía con acceso directo a Ajustes. Así nunca se solapan los dos mensajes.
    private func promptForPermission() {
        let askedKey = "klip.askedScreenRecording"
        if !UserDefaults.standard.bool(forKey: askedKey) {
            UserDefaults.standard.set(true, forKey: askedKey)
            ScreenCapturer.requestPermission()   // solo el prompt nativo la primera vez
            return
        }
        let alert = NSAlert()
        alert.messageText = "Klip necesita permiso de Grabación de pantalla"
        alert.informativeText = "Para capturar una región de la pantalla, concede acceso a Klip en "
            + "Ajustes del Sistema › Privacidad y seguridad › Grabación de pantalla. "
            + "Tras concederlo, vuelve a pulsar el atajo de captura."
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Cancelar")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
