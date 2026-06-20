import Foundation
import AppKit

/// Errores tipados de la subida de capturas (estilo Lightshot). Mensajes en español listos para mostrar.
enum UploadError: Error, LocalizedError {
    case invalidEndpoint            // el endpoint configurado no forma una URL válida
    case encodingFailed             // no se pudo obtener el PNG de la imagen
    case transport(Error)           // sin red / fallo de transporte (URLSession lanzó)
    case http(status: Int)          // el servidor respondió con un código != 2xx
    case invalidResponse            // respuesta vacía o sin la URL esperada en el JSON

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:  return "El servidor de subida no es una dirección válida."
        case .encodingFailed:   return "No se pudo preparar la imagen (PNG)."
        case .transport(let e): return "Error de red al subir: \(e.localizedDescription)"
        case .http(let status): return "El servidor respondió con error (HTTP \(status))."
        case .invalidResponse:  return "La respuesta del servidor no es válida."
        }
    }
}

/// Cliente de subida de capturas a un servidor propio (estilo Lightshot).
/// Sube una imagen PNG por multipart a `<uploadEndpoint>/upload` (campo `file`) y devuelve la URL
/// pública que regresa el backend en JSON: `{"url": "https://…/XXXXXX.png"}`.
/// Los links se auto-purgan a los 3 días en el servidor (etapa de pruebas).
final class UploaderClient {
    static let shared = UploaderClient()
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    /// Endpoint base de subida (configurable en Preferencias). Se lee en cada subida para reflejar
    /// cambios en caliente; sin barra final para concatenar `/upload` limpio.
    private var endpoint: String {
        Settings.shared.uploadEndpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Sube una NSImage como PNG y devuelve la URL pública. Lanza `UploadError` tipado.
    func upload(image: NSImage) async throws -> URL {
        guard let png = Storage.shared.pngData(from: image) else { throw UploadError.encodingFailed }
        return try await upload(pngData: png)
    }

    /// Sube datos PNG ya codificados (evita recodificar si el llamador ya los tiene).
    func upload(pngData: Data) async throws -> URL {
        guard let url = URL(string: "\(endpoint)/upload") else { throw UploadError.invalidEndpoint }

        // Cuerpo multipart/form-data con un único campo `file` = captura.png.
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func append(_ s: String) { if let d = s.data(using: .utf8) { body.append(d) } }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"captura.png\"\r\n")
        append("Content-Type: image/png\r\n\r\n")
        body.append(pngData)
        append("\r\n")
        append("--\(boundary)--\r\n")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 60

        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) }
        catch { throw UploadError.transport(error) }

        guard let http = resp as? HTTPURLResponse else { throw UploadError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw UploadError.http(status: http.statusCode) }

        struct R: Decodable { let url: String }
        guard let r = try? JSONDecoder().decode(R.self, from: data),
              let link = URL(string: r.url) else { throw UploadError.invalidResponse }
        return link
    }
}
