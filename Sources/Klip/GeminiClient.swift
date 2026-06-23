import Foundation

/// Google Gemini client for audio transcription (alternative provider to OpenAI).
/// The key is read from the local file (gemini.key); it is sent via the x-goog-api-key header (not in the URL).
final class GeminiClient {
    static let shared = GeminiClient()
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    var hasAPIKey: Bool {
        guard let v = SecretStore.get(.gemini) else { return false }
        return !v.isEmpty
    }

    private func apiKey() throws -> String {
        guard let v = SecretStore.get(.gemini), !v.isEmpty else { throw OpenAIError.missingAPIKey }
        return v
    }

    /// `model` is resolved on the MainActor by the caller (Recorder) and passed in here, so we don't read
    /// `Settings.shared` from the transcription thread (avoids the data race with a @Published).
    func transcribe(audioURL: URL, language: String?, model: String, vocabulary: String = "") async throws -> String {
        let key = try apiKey()
        let resolvedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "gemini-flash-latest" : model.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try Data(contentsOf: audioURL)
        let base64 = data.base64EncodedString()
        // No language hint when "auto-detect": let the model transcribe in the audio's own language.
        let langHint = (language?.isEmpty == false) ? " Primary language: \(language!)." : ""
        let vocab = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        let vocabHint = vocab.isEmpty ? ""
            : " These names/terms may appear; spell them exactly as written: \(vocab)."
        let prompt = "Transcribe this audio verbatim. Return ONLY the transcription, "
            + "with no comments, headings or formatting.\(langHint)\(vocabHint)"

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(resolvedModel):generateContent")!

        // `thinkingBudget:0` disables the reasoning step (the "-latest" alias now resolves to a thinking
        // model that burns "thought" tokens and can return an empty answer for a plain transcription). But
        // some user-selectable models reject thinkingConfig with a 400 — in that case retry once without it.
        func send(includeThinking: Bool) async throws -> Data {
            var gen: [String: Any] = ["temperature": 0]
            if includeThinking { gen["thinkingConfig"] = ["thinkingBudget": 0] }
            let payload: [String: Any] = [
                "contents": [["role": "user", "parts": [
                    ["inline_data": ["mime_type": Self.mimeType(for: audioURL), "data": base64]],
                    ["text": prompt]
                ]]],
                "generationConfig": gen
            ]
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            req.timeoutInterval = 120

            let respData: Data, resp: URLResponse
            do { (respData, resp) = try await session.data(for: req) } catch { throw OpenAIError.transport(error) }
            guard let http = resp as? HTTPURLResponse else { throw OpenAIError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                struct E: Decodable { struct Err: Decodable { let message: String }; let error: Err }
                let msg = (try? JSONDecoder().decode(E.self, from: respData))?.error.message
                    ?? (String(data: respData, encoding: .utf8) ?? "")
                if http.statusCode == 400, includeThinking, msg.lowercased().contains("thinking") {
                    return try await send(includeThinking: false)   // this model doesn't accept thinkingConfig
                }
                throw OpenAIError.http(status: http.statusCode, message: "Gemini: \(msg)")
            }
            return respData
        }
        let respData = try await send(includeThinking: true)

        struct R: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String?; let thought: Bool? }
                    let parts: [Part]?
                }
                let content: Content?
            }
            let candidates: [Candidate]?
        }
        guard let r = try? JSONDecoder().decode(R.self, from: respData) else { throw OpenAIError.invalidResponse }
        let text = (r.candidates?.first?.content?.parts ?? [])
            .filter { $0.thought != true }      // skip reasoning parts; keep only the answer
            .compactMap { $0.text }
            .joined()
        // A 200 with no usable text means the model returned nothing (safety block, token-budget cutoff,
        // empty candidate) — surface it as an error so it's logged and distinguishable from real silence.
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIError.invalidResponse
        }
        return text
    }

    /// Audio MIME types that Gemini accepts. .m4a/.mp4/.m4b are MP4 containers (audio/mp4); reserve
    /// audio/aac for genuine ADTS .aac streams.
    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3", "mpeg", "mpga":        return "audio/mp3"
        case "wav":                        return "audio/wav"
        case "aiff", "aif":                return "audio/aiff"
        case "ogg", "oga", "opus":         return "audio/ogg"
        case "flac":                       return "audio/flac"
        case "aac":                        return "audio/aac"
        case "m4a", "mp4", "m4b":          return "audio/mp4"
        default:                           return "audio/mp4"
        }
    }
}

/// Selects the configured AI provider for transcription.
enum AIProvider {
    static var selected: String { Settings.shared.aiProvider }

    /// Is the selected provider ready? Local (on-device) needs no key; each cloud provider needs ITS OWN
    /// key (no cross-provider fallback — picking Gemini and having only an OpenAI key must not silently
    /// send your audio to OpenAI; the UI shows exactly the selected provider's key section).
    static var hasKey: Bool {
        switch selected {
        case "local":  return true
        case "gemini": return GeminiClient.shared.hasAPIKey
        default:       return OpenAIClient.shared.hasAPIKey
        }
    }

    /// Routes on the EFFECTIVE provider resolved by the caller on the MainActor (no Settings re-read here,
    /// so there's no off-main data race and no provider/model TOCTOU). `model` already matches `provider`.
    static func transcribe(provider: String, audioURL: URL, language: String?, model: String, vocabulary: String = "") async throws -> String {
        switch provider {
        case "local":
            // On-device (WhisperKit): no audio leaves the Mac. `model` is the on-device model name.
            return try await LocalTranscriber.shared.transcribe(audioURL: audioURL, model: model, language: language, vocabulary: vocabulary)
        case "gemini":
            return try await GeminiClient.shared.transcribe(audioURL: audioURL, language: language, model: model, vocabulary: vocabulary)
        default:
            return try await OpenAIClient.shared.transcribe(audioURL: audioURL, language: language, model: model, vocabulary: vocabulary)
        }
    }
}
