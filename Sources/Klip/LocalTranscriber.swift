import Foundation
import WhisperKit

/// On-device transcription with WhisperKit (Whisper on Core ML). No audio leaves the Mac and no API key
/// is needed. The Core ML model is downloaded once on first use and cached; the pipeline is kept in memory
/// and reused while the chosen model doesn't change.
actor LocalTranscriber {
    static let shared = LocalTranscriber()

    private var pipe: WhisperKit?
    private var loadedModel: String?

    /// Friendly model name → WhisperKit model identifier (WhisperKit resolves these against its HF repo).
    static let models: [(id: String, label: String, note: String)] = [
        ("tiny",        "Tiny",        "~75 MB · fastest, lowest accuracy"),
        ("base",        "Base",        "~145 MB · good balance (recommended)"),
        ("small",       "Small",       "~480 MB · more accurate, slower"),
        ("large-v3_turbo", "Large v3 Turbo", "~1.5 GB · best accuracy"),
    ]
    static let defaultModel = "base"

    /// Transcribes an audio file fully on-device. `model` is a WhisperKit model name (see `models`).
    /// `vocabulary` (context words/names) biases recognition via Whisper prompt tokens.
    func transcribe(audioURL: URL, model: String, language: String?, vocabulary: String) async throws -> String {
        let wk = try await pipeline(for: model.isEmpty ? Self.defaultModel : model)
        var opts = DecodingOptions()
        opts.task = .transcribe
        opts.skipSpecialTokens = true
        opts.withoutTimestamps = true
        if let language, !language.isEmpty {
            opts.language = language          // explicit audio language
            opts.detectLanguage = false
        } else {
            opts.detectLanguage = true        // "auto-detect"
        }
        // Bias toward the user's context words/names (same idea as the cloud `prompt`): encode them as
        // Whisper prompt tokens. WhisperKit also strips special tokens and caps length internally.
        let vocab = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !vocab.isEmpty, let tok = wk.tokenizer {
            let ids = tok.encode(text: " " + vocab).filter { $0 < tok.specialTokens.specialTokenBegin }
            if !ids.isEmpty {
                opts.promptTokens = Array(ids.suffix(200))
                opts.usePrefillPrompt = true
            }
        }
        let results = try await wk.transcribe(audioPath: audioURL.path, decodeOptions: opts)
        return results.map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pipeline(for model: String) async throws -> WhisperKit {
        if let pipe, loadedModel == model { return pipe }
        let wk = try await WhisperKit(WhisperKitConfig(model: model))   // downloads the model on first use
        pipe = wk
        loadedModel = model
        return wk
    }
}
