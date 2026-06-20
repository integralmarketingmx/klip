import AppKit

/// Método D — "Mail del sistema": abre el compositor de correo NATIVO del sistema
/// (`NSSharingService(named: .composeEmail)`) con la imagen como adjunto y el
/// asunto/cuerpo prellenados. Cero backend: usa la cuenta configurada en Mail.app
/// (o el cliente por defecto). Si `.composeEmail` no está disponible, cae a un
/// `NSSharingServicePicker` anclado a una vista.
///
/// Nota: el servicio de Apple toma asunto/cuerpo de las propiedades del servicio y
/// la imagen como item compartido. No permite forzar destinatarios de forma fiable
/// entre clientes, así que el destinatario se prellena cuando es posible vía recipients.
enum SystemMailSender {

    /// Escribe el PNG a un archivo temporal y devuelve su URL (para adjuntarlo como item).
    /// El compositor nativo adjunta mejor un archivo en disco que un `NSImage` suelto.
    private static func writeTempPNG(_ png: Data, name: String) -> URL? {
        let safe = name.isEmpty ? "captura.png" : name
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("klip-mail-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(safe)
        do { try png.write(to: url); return url } catch { return nil }
    }

    /// Intenta abrir el compositor nativo. Devuelve `true` si se pudo presentar.
    /// - Parameters:
    ///   - anchor: vista a la que anclar el `NSSharingServicePicker` de respaldo (opcional).
    @discardableResult
    @MainActor
    static func compose(subject: String,
                        body: String,
                        recipients: [String],
                        png: Data?,
                        attachmentName: String = "captura.png",
                        anchor: NSView? = nil) -> Bool {
        // Items a compartir: el cuerpo (texto) y, si hay, el adjunto (archivo PNG en disco).
        var items: [Any] = [body]
        if let png, let url = writeTempPNG(png, name: attachmentName) {
            items.append(url)
        }

        // Camino preferido: NSSharingService .composeEmail.
        if let svc = NSSharingService(named: .composeEmail), svc.canPerform(withItems: items) {
            svc.subject = subject
            svc.recipients = recipients.filter { !$0.isEmpty }
            svc.perform(withItems: items)
            return true
        }

        // Respaldo: picker de compartir anclado a una vista (deja elegir Mail u otro).
        guard let anchor else { return false }
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        return true
    }
}
