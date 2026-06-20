import AppKit
import SwiftUI

// MARK: - Captura + anotación (vibe coders)
extension PanelController {

    /// Captura una zona (selector nativo) o la pantalla completa y abre el editor de anotación.
    func captureAndAnnotate(fullScreen: Bool) {
        // Si el historial está fijado (always on top), no lo cerramos al capturar.
        if !Settings.shared.alwaysOnTop { hide(restoreFocus: false) }
        capturing = true   // que el clic de selección no auto-cierre el panel fijado
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("klipcap-\(UUID().uuidString).png")
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = fullScreen ? ["-m", tmp.path] : ["-i", "-o", tmp.path]
            try? p.run(); p.waitUntilExit()
            let img = (try? Data(contentsOf: tmp)).flatMap { NSImage(data: $0) }   // carga completa antes de borrar
            try? FileManager.default.removeItem(at: tmp)
            DispatchQueue.main.async {
                self.capturing = false
                guard let img else { return }   // el usuario canceló o faltó permiso de grabación de pantalla
                // Copia al portapapeles de inmediato: el usuario puede pegar (⌘V) sin tocar la miniatura.
                self.manager.copyCapturedToClipboard(img)
                // Miniatura estilo macOS: clic → editar; ignorar → solo guardar en Klip.
                let preview = CapturePreviewController(
                    image: img,
                    onEdit: { [weak self] image in self?.showAnnotationWindow(image: image) },
                    onSaveOnly: { [weak self] image in self?.manager.addCapturedImage(image) })
                preview.show()
            }
        }
    }

    /// Reabre el anotador con una imagen ya existente del historial (botón "Ver en grande").
    /// Lo anotado entra como elemento NUEVO (la original se conserva), igual que al capturar.
    func annotateExistingImage(_ item: ClipboardItem) {
        guard item.kind == .image, let fn = item.imageFileName,
              let img = NSImage(contentsOf: Storage.shared.imageURL(for: fn)) else { return }
        if !Settings.shared.alwaysOnTop { hide(restoreFocus: false) }
        showAnnotationWindow(image: img)
    }

    func showAnnotationWindow(image: NSImage) {
        // Escala la captura para que quepa ENTERA en la pantalla visible (zoom out):
        // así la barra de herramientas no tapa contenido y el usuario no necesita hacer scroll.
        let toolbarH: CGFloat = 56          // alto aprox. de la barra de herramientas
        let margin: CGFloat = 48            // aire alrededor de la ventana
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let displaySize = PanelPositioner.annotationDisplaySize(
            imageSize: image.size, visibleFrame: visible, toolbarHeight: toolbarH, margin: margin)

        let view = AnnotationView(
            image: image,
            displaySize: displaySize,
            onAddToKlip: { [weak self] img in self?.manager.addCapturedImage(img) },
            onClose: { [weak self] in self?.annotationWindow?.close() },
            onSendEmail: { [weak self] img in self?.composeEmailWithImage(img) })
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0,
                                width: displaySize.width,
                                height: displaySize.height + toolbarH),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Anotar captura"
        w.isReleasedWhenClosed = false
        // Se mantiene SIEMPRE visible (por encima, sin desaparecer al cambiar de app) hasta que el
        // usuario cierre/guarde/Esc/⌘W. Antes podía esfumarse al perder el foco.
        w.level = .floating
        w.hidesOnDeactivate = false
        w.contentView = NSHostingView(rootView: view)
        w.center()
        // Cierra una ventana de anotación previa (evita acumular NSWindow huérfanas con
        // isReleasedWhenClosed=false) y limpia la referencia al cerrarse por CUALQUIER vía
        // (X roja incluida), no solo por el callback onClose de la vista.
        annotationWindow?.delegate = nil
        annotationWindow?.close()
        let closer = WindowCloser { [weak self, weak w] in
            if self?.annotationWindow === w { self?.annotationWindow = nil }
            self?.annotationCloser = nil
        }
        w.delegate = closer
        annotationCloser = closer
        annotationWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
