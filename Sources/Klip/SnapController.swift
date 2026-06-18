import AppKit

/// Orquesta el flujo de captura "Klip Snap": permiso → captura del display bajo el cursor →
/// overlay de selección → editor de anotaciones → historial de Klip.
final class SnapController {
    private let manager: ClipboardManager
    private var overlay: CaptureOverlayController?
    private var editor: SnapEditorController?
    private var inProgress = false

    /// Se invoca tras añadir una captura al historial (para revelar el panel: el item "vuela" a Klip).
    var onCaptured: (() -> Void)?

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
            defer { self.inProgress = false }
            do {
                let shot = try await ScreenCapturer.captureDisplay(containing: mouse)
                self.presentOverlay(shot)
            } catch CaptureError.noPermission {
                self.promptForPermission()
            } catch {
                NSSound.beep()
            }
        }
    }

    @MainActor
    private func presentOverlay(_ shot: DisplayShot) {
        let overlay = CaptureOverlayController(shot: shot) { [weak self] image in
            self?.overlay = nil
            guard let self, let image else { return }
            self.openEditor(with: image)
        }
        self.overlay = overlay
        overlay.present()
    }

    @MainActor
    private func openEditor(with image: NSImage) {
        let editor = SnapEditorController(image: image) { [weak self] result in
            self?.editor = nil
            guard let self, let result else { return }   // nil = cerrado sin guardar
            self.manager.addAnnotatedScreenshot(result, copyToClipboard: true)
            self.onCaptured?()
        }
        self.editor = editor
        editor.present()
    }

    /// Sin permiso de Grabación de pantalla: explica y abre Ajustes del sistema.
    private func promptForPermission() {
        let alert = NSAlert()
        alert.messageText = "Klip necesita permiso de Grabación de pantalla"
        alert.informativeText = "Para capturar una región de la pantalla, concede acceso a Klip en "
            + "Ajustes del Sistema › Privacidad y seguridad › Grabación de pantalla. "
            + "Tras concederlo, vuelve a pulsar el atajo de captura."
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Cancelar")
        ScreenCapturer.requestPermission()   // dispara el prompt nativo la primera vez
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
