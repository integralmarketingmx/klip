import AppKit
import SwiftUI

// MARK: - Compositor de email (enviar captura por correo vía server Klip /send)
extension PanelController {

    /// Sube la captura (si hace falta el slug para correlación) y abre el compositor de email.
    /// Para mantener el alcance: si la subida falla, igual abrimos el compositor pero sin slug;
    /// el adjunto va directo en la request, así el correo se puede mandar de todos modos.
    func composeEmail(_ item: ClipboardItem) {
        guard item.kind == .image, let fn = item.imageFileName,
              let img = Storage.shared.loadImage(fileName: fn),
              let png = Storage.shared.pngData(from: img) else { return }

        Task { @MainActor in
            var slug = ""
            // Intento best-effort: subir para tener link + slug (correlación del inbox).
            if let link = try? await UploaderClient.shared.upload(pngData: png, ocrText: item.text) {
                // El slug es el nombre del archivo sin extensión del último componente de la URL.
                slug = (link.lastPathComponent as NSString).deletingPathExtension
            }
            let subject = "Captura de Klip" + (item.name.map { " · \($0)" } ?? "")
            var bodyLines = ["Te comparto una captura desde Klip."]
            if let ocr = item.text?.trimmingCharacters(in: .whitespacesAndNewlines), !ocr.isEmpty {
                bodyLines.append("")
                bodyLines.append("Texto detectado (OCR):")
                bodyLines.append(ocr)
            }
            presentEmailComposer(slug: slug, attachment: png,
                                 subject: subject, body: bodyLines.joined(separator: "\n"))
        }
    }

    /// Presenta la ventana del compositor SwiftUI.
    private func presentEmailComposer(slug: String, attachment: Data?, subject: String, body: String) {
        let view = EmailComposerView(
            ownerEmail: "",                 // en pruebas no conocemos al "dueño"; el usuario escribe el destino
            slug: slug,
            attachment: attachment,
            initialSubject: subject,
            initialBody: body,
            onClose: { [weak self] in
                self?.emailWindow?.orderOut(nil)
                self?.emailWindow = nil
                self?.modalCount -= 1
            }
        )
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Enviar por email"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.center()
        emailWindow = w
        modalCount += 1                     // no auto-cerrar el panel mientras el compositor está abierto
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
