import Foundation
import WhisperKit

/// On-device transcription with WhisperKit (Whisper on Core ML). No audio leaves the Mac and no API key
/// is needed. The Core ML model is downloaded once on first use and cached; the pipeline is kept in memory
/// and reused while the chosen model doesn't change.
actor LocalTranscriber {
    static let shared = LocalTranscriber()

    private var pipe: WhisperKit?
    private var loadedModel: String?
    /// Serializes on-device decodes: the shared WhisperKit instance has mutable state (progress, timings,
    /// Core ML decoder) that is NOT safe to run concurrently. Dropping several audio files at once would
    /// otherwise race. Each call chains after the previous one's decode.
    private var serialTail: Task<Void, Never> = Task {}

    /// Friendly model name → WhisperKit model identifier (WhisperKit resolves these against its HF repo).
    static let models: [(id: String, label: String, note: String)] = [
        ("tiny",        "Tiny",        "~75 MB · fastest · lowest accuracy"),
        ("base",        "Base",        "~145 MB · fast · good balance (recommended)"),
        ("small",       "Small",       "~480 MB · slower · more accurate"),
        ("large-v3_turbo", "Large v3 Turbo", "~1.5 GB · slowest · best accuracy"),
    ]
    static let defaultModel = "base"

    /// Loads (and, if needed, downloads) the configured model ahead of time so the first voice note isn't
    /// stuck waiting. Best-effort: called on launch when the on-device provider is active.
    func prewarm(model: String) async {
        _ = try? await pipeline(for: model.isEmpty ? Self.defaultModel : model)
    }

    /// Whether the model is already on disk (so the next transcription won't trigger a first-use download).
    /// Used to show a distinct "Downloading model…" state instead of the generic "Transcribing…".
    nonisolated static func isModelReady(_ model: String) -> Bool {
        let id = model.isEmpty ? defaultModel : model
        guard let base = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: false) else { return false }
        let dir = base.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return false }
        return entries.contains { $0.contains(id) }   // e.g. "openai_whisper-base", "…large-v3_turbo…"
    }

    /// Transcribes an audio file fully on-device. `model` is a WhisperKit model name (see `models`).
    /// `vocabulary` (context words/names) biases recognition via Whisper prompt tokens.
    /// Public entry: serializes decodes on the shared pipeline (see `serialTail`).
    func transcribe(audioURL: URL, model: String, language: String?, vocabulary: String) async throws -> String {
        let previous = serialTail
        let job = Task<String, Error> {
            _ = await previous.value   // wait for any in-flight decode before touching the shared WhisperKit
            return try await self.performTranscribe(audioURL: audioURL, model: model, language: language, vocabulary: vocabulary)
        }
        serialTail = Task { _ = try? await job.value }   // next call chains after this one
        return try await job.value
    }

    private func performTranscribe(audioURL: URL, model: String, language: String?, vocabulary: String) async throws -> String {
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
        let wk: WhisperKit
        do {
            wk = try await WhisperKit(WhisperKitConfig(model: model))   // downloads the model on first use
            loadedModel = model
        } catch {
            // A bad/unavailable model id (or a failed download for that variant) shouldn't break every
            // transcription — fall back to the default model rather than failing hard.
            guard model != Self.defaultModel else { throw error }
            wk = try await WhisperKit(WhisperKitConfig(model: Self.defaultModel))
            loadedModel = Self.defaultModel
        }
        pipe = wk
        return wk
    }
}
