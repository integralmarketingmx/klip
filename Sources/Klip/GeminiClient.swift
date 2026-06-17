import Foundation

/// Cliente de Google Gemini para transcripción de audio (proveedor alternativo a OpenAI).
/// La clave se lee del archivo local (gemini.key); se envía por el header x-goog-api-key (no en la URL).
final class GeminiClient {
    static let shared = GeminiClient()
    private let session: URLSession
    private let model = "gemini-flash-latest"   // alias siempre al último flash (evita 404 por deprecación)
    init(session: URLSession = .shared) { self.session = session }

    var hasAPIKey: Bool {
        guard let v = SecretStore.get(.gemini) else { return false }
        return !v.isEmpty
    }

    private func apiKey() throws -> String {
        guard let v = SecretStore.get(.gemini), !v.isEmpty else { throw OpenAIError.missingAPIKey }
        return v
    }

    func transcribe(audioURL: URL, language: String?) async throws -> String {
        let key = try apiKey()
        let data = try Data(contentsOf: audioURL)
        let base64 = data.base64EncodedString()
        let lang = (language?.isEmpty == false) ? language! : "es"
        let prompt = "Transcribe este audio a texto literal. Devuelve SOLO la transcripción, "
            + "sin comentarios, encabezados ni formato. Idioma principal: \(lang)."

        let payload: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["inline_data": ["mime_type": Self.mimeType(for: audioURL), "data": base64]],
                    ["text": prompt]
                ]
            ]],
            "generationConfig": ["temperature": 0]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 120

        let respData: Data, resp: URLResponse
        do { (respData, resp) = try await session.data(for: req) } catch { throw OpenAIError.transport(error) }
        guard let http = resp as? HTTPURLResponse else { throw OpenAIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            struct E: Decodable { struct Err: Decodable { let message: String }; let error: Err }
            let msg = (try? JSONDecoder().decode(E.self, from: respData))?.error.message
                ?? (String(data: respData, encoding: .utf8) ?? "")
            throw OpenAIError.http(status: http.statusCode, message: "Gemini: \(msg)")
        }

        struct R: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable { struct Part: Decodable { let text: String? }; let parts: [Part]? }
                let content: Content?
            }
            let candidates: [Candidate]?
        }
        guard let r = try? JSONDecoder().decode(R.self, from: respData) else { throw OpenAIError.invalidResponse }
        let text = (r.candidates?.first?.content?.parts ?? [])
            .compactMap { $0.text }
            .joined()
        return text
    }

    /// Tipos MIME de audio que acepta Gemini (best-effort; .m4a/AAC → audio/aac).
    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3", "mpeg", "mpga":        return "audio/mp3"
        case "wav":                        return "audio/wav"
        case "aiff", "aif":                return "audio/aiff"
        case "ogg", "oga", "opus":         return "audio/ogg"
        case "flac":                       return "audio/flac"
        case "m4a", "aac", "mp4", "m4b":   return "audio/aac"
        default:                           return "audio/aac"
        }
    }
}

/// Selecciona el proveedor de IA configurado para transcribir.
enum AIProvider {
    static var selected: String { Settings.shared.aiProvider }

    /// ¿Hay clave para el proveedor seleccionado (con respaldo a OpenAI si Gemini no tiene clave)?
    static var hasKey: Bool {
        if selected == "gemini" { return GeminiClient.shared.hasAPIKey || OpenAIClient.shared.hasAPIKey }
        return OpenAIClient.shared.hasAPIKey
    }

    static func transcribe(audioURL: URL, language: String?, model: String) async throws -> String {
        if selected == "gemini", GeminiClient.shared.hasAPIKey {
            return try await GeminiClient.shared.transcribe(audioURL: audioURL, language: language)
        }
        return try await OpenAIClient.shared.transcribe(audioURL: audioURL, language: language, model: model)
    }
}
