import AppKit

// MARK: - Anotar una imagen existente del historial con el editor Snap
//
// La captura nueva (⌘⇧U / menú) la maneja SnapController (ScreenCaptureKit + overlay), cableado en
// AppDelegate. Aquí solo queda "Editar / anotar" sobre una imagen YA existente del historial:
// abre el mismo editor Snap con esa imagen; lo anotado entra como elemento NUEVO (la original se
// conserva), igual que una captura.
extension PanelController {

    func annotateExistingImage(_ item: ClipboardItem) {
        guard item.kind == .image, let fn = item.imageFileName,
              let img = NSImage(contentsOf: Storage.shared.imageURL(for: fn)) else { return }
        if !Settings.shared.alwaysOnTop { hide(restoreFocus: false) }
        let editor = SnapEditorController(image: img) { [weak self] result in
            self?.snapEditor = nil
            guard let self, let result else { return }   // nil = cerrado sin guardar
            self.manager.addAnnotatedScreenshot(result, copyToClipboard: true)
        }
        editor.onSendEmail = { [weak self] image in self?.composeEmailWithImage(image) }
        snapEditor = editor            // retiene el editor mientras la ventana está abierta
        editor.present()
    }
}
