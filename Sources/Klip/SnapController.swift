import AppKit

/// Orchestrates the "Klip Snap" capture flow: permission → capture the display under the cursor →
/// selection overlay → annotation editor → Klip history.
final class SnapController {
    private let manager: ClipboardManager
    private var overlay: CaptureOverlayController?
    private var editor: SnapEditorController?
    private var inProgress = false

    /// Invoked after adding a capture to the history (to reveal the panel: the item "flies" to Klip).
    var onCaptured: (() -> Void)?

    init(manager: ClipboardManager) {
        self.manager = manager
        ScreenCapturer.warmUp()
    }

    /// Entry point (shortcut or menu).
    func start() {
        // Block re-entry for the WHOLE flow: while capturing (inProgress) and while the selection overlay
        // or the editor is on screen. Otherwise a second ⌘⇧U would stack shield windows and leak the first.
        guard !inProgress, overlay == nil, editor == nil else { return }

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
                self.inProgress = false          // release BEFORE the modal (avoids runloop reentrancy)
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
            self.openEditor(with: image)
        }
        self.overlay = overlay
        overlay.present()
    }

    @MainActor
    private func openEditor(with image: NSImage) {
        let editor = SnapEditorController(image: image) { [weak self] result in
            self?.editor = nil
            guard let self, let result else { return }   // nil = closed without saving
            self.manager.addAnnotatedScreenshot(result, copyToClipboard: true)
            self.onCaptured?()
        }
        self.editor = editor
        editor.present()
    }

    /// No Screen Recording permission. The FIRST time we only show the native system prompt
    /// (`requestPermission`); on later attempts (when the native prompt no longer reappears) we show
    /// our own guide with a shortcut to Settings. This way the two messages never overlap.
    private func promptForPermission() {
        let askedKey = "klip.askedScreenRecording"
        if !UserDefaults.standard.bool(forKey: askedKey) {
            UserDefaults.standard.set(true, forKey: askedKey)
            ScreenCapturer.requestPermission()   // only the native prompt the first time
            return
        }
        let alert = NSAlert()
        alert.messageText = L10n.t("perm.screen.title")
        alert.informativeText = L10n.t("perm.screen.info")
        alert.addButton(withTitle: L10n.t("perm.screen.open"))
        alert.addButton(withTitle: L10n.t("common.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
