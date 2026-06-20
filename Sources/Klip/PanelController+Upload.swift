import AppKit

// MARK: - Subida de imagen (estilo Lightshot) + toast de confirmación
extension PanelController {

    /// Sube la imagen del elemento al servidor (estilo Lightshot) y, al éxito, copia el link al
    /// portapapeles y muestra una confirmación breve NO-modal. Al fallar muestra el error real.
    /// `async`: la fila la invoca dentro de un Task para mostrar su propio spinner mientras sube.
    func uploadAndCopyLink(_ item: ClipboardItem) async {
        guard item.kind == .image, let fn = item.imageFileName,
              let img = Storage.shared.loadImage(fileName: fn) else { return }
        do {
            let link = try await UploaderClient.shared.upload(image: img)
            manager.setClipboardText(link.absoluteString)   // evita re-capturar la URL como item nuevo
            showUploadToast(link)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showAlert("No se pudo subir la imagen", msg)
        }
    }

    /// Confirmación breve no-modal: panel flotante que se auto-cierra a los pocos segundos.
    private func showUploadToast(_ link: URL) {
        uploadToastWindow?.orderOut(nil)

        let text = "✓ Link copiado al portapapeles\n\(link.absoluteString)"
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        let size = NSSize(width: 380, height: 64)
        let win = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.hasShadow = true
        win.ignoresMouseEvents = true
        win.contentView = container
        // Centrado horizontal, cerca del borde inferior de la pantalla con el panel.
        if let screen = (panel.screen ?? NSScreen.main)?.visibleFrame {
            let x = screen.midX - size.width / 2
            let y = screen.minY + 80
            win.setFrameOrigin(NSPoint(x: x, y: y))
        }
        win.orderFront(nil)
        uploadToastWindow = win

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            guard self?.uploadToastWindow === win else { return }
            win.orderOut(nil)
            self?.uploadToastWindow = nil
        }
    }
}
