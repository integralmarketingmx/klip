import Foundation
import AppKit

/// Errores tipados del envío de email por el server Klip (POST /send).
enum MailError: Error, LocalizedError {
    case invalidEndpoint          // el endpoint configurado no forma una URL válida
    case missingToken             // falta el shared secret (KLIP_API_TOKEN) en Preferencias
    case noRecipients             // no se indicó ningún destinatario
    case transport(Error)         // sin red / fallo de transporte
    case http(status: Int, body: String)  // el server respondió != 2xx
    case invalidResponse          // respuesta inesperada

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:  return "El servidor de email no es una dirección válida."
        case .missingToken:     return "Falta el token de API de Klip (configúralo en Preferencias)."
        case .noRecipients:     return "Agrega al menos un destinatario."
        case .transport(let e): return "Error de red al enviar: \(e.localizedDescription)"
        case .http(let s, let b): return "El servidor respondió con error (HTTP \(s)). \(b)"
        case .invalidResponse:  return "La respuesta del servidor no es válida."
        }
    }
}

/// Config SMTP que viaja al backend cuando el método es .smtp (la pass va por HTTPS).
struct SMTPConfig {
    var host: String
    var port: Int
    var user: String
    var pass: String
    var from: String
}

/// Datos del correo a enviar; el server arma el MIME y lo manda según `method`.
struct MailDraft {
    var from: String
    var to: [String]
    var cc: [String]
    var bcc: [String]
    var subject: String
    var body: String
    var slug: String                 // slug Klip para correlación (puede ir vacío)
    var attachment: Data?            // PNG opcional a adjuntar directamente (la captura)
    var attachmentName: String = "captura.png"
    /// Adjuntos extra (archivos que el usuario agrega en el compositor).
    var extraAttachments: [MailAttachment] = []
    /// Método de transporte para el backend: "oauth" (Google Workspace per-usuario, default) o "smtp".
    var method: String = "oauth"
    /// Config SMTP (solo si method == "smtp").
    var smtp: SMTPConfig?
    /// Access token del usuario (solo si method == "oauth").
    var accessToken: String?
}

/// Un adjunto de correo (archivo agregado por el usuario en el compositor).
struct MailAttachment: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var mime: String
    var data: Data
}

/// Cliente del endpoint POST /send del server Klip. Manda multipart si hay adjunto,
/// si no, JSON. Protege con el shared secret en el header `X-Klip-Token`.
final class MailClient {
    static let shared = MailClient()
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    /// Endpoint base (reusa el mismo que la subida de capturas).
    private var endpoint: String {
        Settings.shared.uploadEndpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func send(_ draft: MailDraft) async throws {
        guard let url = URL(string: "\(endpoint)/send") else { throw MailError.invalidEndpoint }
        let token = Settings.shared.mailApiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw MailError.missingToken }
        guard !(draft.to.isEmpty && draft.cc.isEmpty && draft.bcc.isEmpty) else { throw MailError.noRecipients }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(token, forHTTPHeaderField: "X-Klip-Token")
        req.timeoutInterval = 60

        if draft.attachment != nil || !draft.extraAttachments.isEmpty {
            // multipart/form-data con uno o varios adjuntos (cada uno como otra parte "file").
            let boundary = "Boundary-\(UUID().uuidString)"
            var body = Data()
            func append(_ s: String) { if let d = s.data(using: .utf8) { body.append(d) } }
            func field(_ name: String, _ value: String) {
                guard !value.isEmpty else { return }
                append("--\(boundary)\r\n")
                append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
                append(value); append("\r\n")
            }
            field("from", draft.from)
            field("to", draft.to.joined(separator: ","))
            field("cc", draft.cc.joined(separator: ","))
            field("bcc", draft.bcc.joined(separator: ","))
            field("subject", draft.subject)
            field("body", draft.body)
            field("slug", draft.slug)
            field("method", draft.method)
            if draft.method == "oauth", let at = draft.accessToken { field("accessToken", at) }
            if draft.method == "smtp", let s = draft.smtp {
                field("smtpHost", s.host)
                field("smtpPort", String(s.port))
                field("smtpUser", s.user)
                field("smtpPass", s.pass)
                field("smtpFrom", s.from)
            }
            func fileField(_ filename: String, mime: String, data: Data) {
                append("--\(boundary)\r\n")
                append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
                append("Content-Type: \(mime)\r\n\r\n")
                body.append(data); append("\r\n")
            }
            if let png = draft.attachment { fileField(draft.attachmentName, mime: "image/png", data: png) }
            for att in draft.extraAttachments { fileField(att.name, mime: att.mime, data: att.data) }
            append("--\(boundary)--\r\n")
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        } else {
            // JSON.
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var payload: [String: Any] = [
                "from": draft.from, "to": draft.to, "cc": draft.cc, "bcc": draft.bcc,
                "subject": draft.subject, "body": draft.body, "slug": draft.slug,
                "method": draft.method,
            ]
            if draft.method == "oauth", let at = draft.accessToken { payload["accessToken"] = at }
            if draft.method == "smtp", let s = draft.smtp {
                payload["smtp"] = [
                    "host": s.host, "port": s.port, "user": s.user, "pass": s.pass, "from": s.from,
                ]
            }
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        }

        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) }
        catch { throw MailError.transport(error) }

        guard let http = resp as? HTTPURLResponse else { throw MailError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MailError.http(status: http.statusCode, body: body)
        }
    }
}
