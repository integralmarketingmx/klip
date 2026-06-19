import Foundation

/// Cliente de Google Gemini para transcripción de audio (proveedor alternativo a OpenAI).
/// La clave se lee del archivo local (gemini.key); se envía por el header x-goog-api-key (no en la URL).
final class GeminiClient {
    static let shared = GeminiClient()
    private let session: URLSession
    /// Modelo configurable en Preferencias. Por defecto "gemini-flash-latest" (alias siempre al último
    /// flash, evita 404 por deprecación). Se lee en cada transcripción para reflejar cambios en caliente.
    private var model: String {
        let m = Settings.shared.geminiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? "gemini-flash-latest" : m
    }
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
            // thinkingBudget 0: para transcribir, "pensar" es desperdicio — el texto es idéntico
            // pero ahorra ~45% del costo (evita ~1.5k thinking tokens) y es más rápido.
            "generationConfig": ["temperature": 0, "thinkingConfig": ["thinkingBudget": 0]]
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

/// Error de transcripción enriquecido: sabe QUÉ proveedor falló y si fue un problema de CLAVE
/// (para que la UI pueda ofrecer pegar una clave nueva en vez de un error genérico).
struct TranscriptionError: Error, LocalizedError {
    let provider: String      // "gemini" | "openai"
    let isAuth: Bool          // true = clave inválida o ausente
    let message: String       // texto legible para mostrar al usuario
    var errorDescription: String? { message }

    /// Clasifica un error subyacente (OpenAIError) como de clave o no.
    static func wrap(_ error: Error, provider: String) -> TranscriptionError {
        let name = provider == "gemini" ? "Gemini" : "OpenAI"
        if let e = error as? OpenAIError {
            switch e {
            case .missingAPIKey:
                return .init(provider: provider, isAuth: true, message: "No hay clave de \(name).")
            case .http(let status, let msg):
                let low = msg.lowercased()
                let keyHint = low.contains("api key") || low.contains("api_key")
                    || low.contains("key not found") || low.contains("invalid argument")
                    || low.contains("unauthenticated") || low.contains("permission")
                let isAuth = status == 401 || status == 403 || (status == 400 && keyHint)
                let reason = isAuth ? "La clave de \(name) no es válida." : "\(name) \(status): \(msg)"
                return .init(provider: provider, isAuth: isAuth, message: reason)
            case .invalidResponse:
                return .init(provider: provider, isAuth: false, message: "Respuesta no válida de \(name).")
            case .transport(let t):
                return .init(provider: provider, isAuth: false, message: "Error de red con \(name): \(t.localizedDescription)")
            }
        }
        return .init(provider: provider, isAuth: false, message: error.localizedDescription)
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

    /// El "otro" proveedor (para el fallback simétrico).
    static func other(of provider: String) -> String { provider == "gemini" ? "openai" : "gemini" }

    /// ¿Hay clave para un proveedor concreto?
    static func hasKey(for provider: String) -> Bool {
        provider == "gemini" ? GeminiClient.shared.hasAPIKey : OpenAIClient.shared.hasAPIKey
    }

    /// Transcribe con UN proveedor concreto (sin fallback). Lanza si no hay clave.
    private static func transcribeWith(_ provider: String, audioURL: URL,
                                       language: String?, model: String) async throws -> String {
        if provider == "gemini" {
            guard GeminiClient.shared.hasAPIKey else { throw OpenAIError.missingAPIKey }
            return try await GeminiClient.shared.transcribe(audioURL: audioURL, language: language)
        }
        guard OpenAIClient.shared.hasAPIKey else { throw OpenAIError.missingAPIKey }
        return try await OpenAIClient.shared.transcribe(audioURL: audioURL, language: language, model: model)
    }

    /// Transcribe con el proveedor PRINCIPAL (el de mayor prioridad, elegido en Preferencias).
    /// Si falla y el fallback está activo (y el OTRO proveedor tiene clave), reintenta con el otro.
    /// `forceProvider` salta la prioridad y el fallback (p. ej. "Usar el otro esta vez").
    /// Lanza `TranscriptionError` (sabe qué proveedor falló y si fue problema de clave).
    static func transcribe(audioURL: URL, language: String?, model: String,
                           forceProvider: String? = nil) async throws -> String {
        let primary = forceProvider ?? selected
        let secondary = other(of: primary)
        do {
            return try await transcribeWith(primary, audioURL: audioURL, language: language, model: model)
        } catch {
            // Fallback automático: solo en flujo normal (no forzado), con switch activo y clave del otro.
            if forceProvider == nil, Settings.shared.transcriptionFallback, hasKey(for: secondary) {
                do { return try await transcribeWith(secondary, audioURL: audioURL, language: language, model: model) }
                catch { throw TranscriptionError.wrap(error, provider: secondary) }
            }
            throw TranscriptionError.wrap(error, provider: primary)
        }
    }
}
