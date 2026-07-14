import Foundation
import AVFoundation
import AppKit
import Combine
import CoreAudio

enum RecorderState: Equatable {
    case idle
    case recording
    case missingAPIKey
    case error(String)      // error PREVIO a grabar (permiso/clave). La transcripción es en segundo plano.
}

/// Graba una nota de voz a .m4a y la transcribe con OpenAI (no en vivo: nota completa).
/// La transcripción corre en segundo plano: al detener, el grabador queda libre para grabar otra.
/// @MainActor (Consejo C2): confina el estado de grabación/transcripción al hilo principal.
@MainActor
final class Recorder: NSObject, ObservableObject, AVAudioRecorderDelegate, AudioRecording {
    @Published private(set) var state: RecorderState = .idle
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var level: Float = 0
    /// true cuando llevamos >2 min en silencio: la UI muestra "¿Sigues ahí?".
    @Published private(set) var silenceWarning = false
    /// Nº de transcripciones en curso en segundo plano (para el indicador de la cabecera).
    @Published private(set) var transcribingCount = 0

    /// El audio ya está guardado: crea el elemento de la nota de voz (placeholder) y devuelve su id.
    /// `audioFileName` puede ser nil si no se pudo guardar el archivo (la transcripción aún se guarda).
    var onVoiceNoteStarted: ((String?, Double?) -> UUID?)?
    /// Rellena la transcripción en el elemento ya creado.
    var onVoiceNoteTranscribed: ((UUID, String) -> Void)?
    /// La transcripción falló o no hubo voz: el elemento queda con el audio para reproducir/recuperar.
    /// El segundo parámetro lleva el motivo (clave inválida, red, etc.) o nil si solo fue "sin voz".
    var onVoiceNoteFailed: ((UUID, TranscriptionError?) -> Void)?
    /// Reintento: marca un elemento existente como "Transcribiendo…" otra vez.
    var onVoiceNoteRetrying: ((UUID) -> Void)?

    // Detección de silencio (timer a 0.1 s): aviso a 2 min, corte a 3 min.
    private var silentTicks = 0
    private let silenceLevel: Float = 0.10
    private let warnTicks = 1200    // 120 s
    private let stopTicks = 1800    // 180 s

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var currentFileName: String?
    /// Persistencia inyectada (Consejo C4): por defecto el singleton; sustituible por un doble.
    private let storage: PersistentStoring

    /// Inyección por constructor con default para no romper a los llamadores (`Recorder()`).
    init(storage: PersistentStoring = Storage.shared) {
        self.storage = storage
        super.init()
    }
    /// Listener de CoreAudio para detectar cambios del micrófono por defecto (p. ej. conectar audífonos).
    /// nonisolated(unsafe): se muta en MainActor (install) y en deinit (nonisolated, al destruir).
    /// El acceso va protegido por `deviceListenerLock` para ser correcto por construcción.
    nonisolated(unsafe) private var deviceListener: AudioObjectPropertyListenerBlock?
    private let deviceListenerLock = NSLock()

    /// Intención de grabar pendiente (cubre la ventana del permiso async).
    private var startRequested = false
    /// true desde que se pide detener hasta que el delegado finaliza (state sigue .recording en ese hueco).
    private(set) var finishing = false
    /// Solo bloquea iniciar otra GRABACIÓN; transcribir en segundo plano no cuenta como ocupado.
    var isRecording: Bool { startRequested || state == .recording }

    private func requestMicPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied:  return false
        case .undetermined:
            return await withCheckedContinuation { cont in
                AVAudioApplication.requestRecordPermission { ok in cont.resume(returning: ok) }
            }
        @unknown default: return false
        }
    }

    @MainActor
    func start() {
        guard !isRecording else { return }
        startRequested = true
        Task { @MainActor in
            guard AIProvider.hasKey else { state = .missingAPIKey; startRequested = false; return }
            guard await requestMicPermission() else {
                state = .error("Permiso de micrófono denegado"); startRequested = false; return
            }
            guard startRequested else { return }   // stop()/cancel() durante la espera del permiso
            let name = "\(UUID().uuidString).m4a"
            let url = storage.audioURL(for: name)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
            do {
                let rec = try AVAudioRecorder(url: url, settings: settings)
                rec.delegate = self
                rec.isMeteringEnabled = true
                guard rec.prepareToRecord(), rec.record() else {
                    state = .error("No se pudo iniciar la grabación"); startRequested = false; return
                }
                recorder = rec
                currentFileName = name
                duration = 0; level = 0
                silentTicks = 0; silenceWarning = false
                state = .recording
                startRequested = false
                startMeterTimer()
                installDeviceListener()
            } catch {
                state = .error(error.localizedDescription); startRequested = false
            }
        }
    }

    @MainActor
    func stop() {
        startRequested = false
        guard state == .recording, !finishing, let rec = recorder else { return }   // ignora doble-stop
        finishing = true
        stopMeterTimer()
        removeDeviceListener()
        rec.stop()   // dispara audioRecorderDidFinishRecording
    }

    @MainActor
    func cancel() {
        startRequested = false
        finishing = false
        stopMeterTimer()
        removeDeviceListener()
        recorder?.delegate = nil   // evita que el delegate sobrescriba .idle con .error
        recorder?.stop()
        recorder = nil
        if let f = currentFileName { storage.deleteAudio(fileName: f) }
        currentFileName = nil
        state = .idle
    }

    // MARK: - Cambio de dispositivo de entrada (audífonos)

    /// Observa el micrófono por defecto. Si cambia DURANTE la grabación (p. ej. conectas audífonos),
    /// AVAudioRecorder se queda en el dispositivo viejo y el medidor se congela → finalizamos la nota
    /// de forma limpia (se guarda y transcribe lo grabado) en vez de dejar un estado roto.
    private func installDeviceListener() {
        deviceListenerLock.lock()
        defer { deviceListenerLock.unlock() }
        guard deviceListener == nil else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.handleInputDeviceChange() } }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
        if status == noErr { deviceListener = block }
    }

    nonisolated private func removeDeviceListener() {
        deviceListenerLock.lock()
        defer { deviceListenerLock.unlock() }
        guard let block = deviceListener else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
        deviceListener = nil
    }

    @MainActor
    private func handleInputDeviceChange() {
        guard state == .recording, !finishing else { return }
        stop()   // finaliza y transcribe lo grabado hasta el cambio de dispositivo
    }

    /// Vuelve a .idle desde estados terminales (error o sin API key) para revalidar al reabrir.
    func reset() {
        switch state {
        case .error, .missingAPIKey: state = .idle
        default: break
        }
    }

    private func startMeterTimer() {
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let rec = self.recorder else { return }
            rec.updateMeters()
            self.duration = rec.currentTime
            let lvl = Self.normalized(power: rec.averagePower(forChannel: 0))
            self.level = lvl
            self.trackSilence(level: lvl)
        }
        RunLoop.main.add(t, forMode: .common)
        meterTimer = t
    }

    private func trackSilence(level lvl: Float) {
        if lvl >= silenceLevel {
            silentTicks = 0
            if silenceWarning { silenceWarning = false }
            return
        }
        silentTicks += 1
        if silentTicks == warnTicks {
            silenceWarning = true
            NSSound.beep()
        } else if silentTicks >= stopTicks {
            MainActor.assumeIsolated { stop() }   // corte por inactividad: finaliza y transcribe
        }
    }

    /// El usuario pulsa "Continuar": resetea el contador de silencio.
    func continueRecording() { silentTicks = 0; silenceWarning = false }

    /// Transcribe uno o varios archivos de audio subidos por el usuario (en segundo plano).
    /// Cada audio se copia a nuestro almacén para poder reproducirlo y conservarlo después.
    @MainActor
    func transcribeFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard AIProvider.hasKey else { state = .missingAPIKey; return }
        for url in urls {
            let stored = storage.importAudio(from: url)                       // copia a audio/ (nil si falla)
            let transcribeURL = stored.map { storage.audioURL(for: $0) } ?? url
            enqueueTranscription(audioFileName: stored, transcribeURL: transcribeURL)
        }
    }

    /// Crea el elemento de la nota de voz con su audio ya guardado y lanza la transcripción.
    /// El audio NUNCA se borra aquí: queda accesible aunque la transcripción falle.
    /// `state` vuelve a .idle de inmediato → el grabador queda libre para grabar otra nota.
    @MainActor
    private func ingest(audioFileName name: String) {
        storage.protectAudio(fileName: name)   // 0600: la grabación contiene voz del usuario
        enqueueTranscription(audioFileName: name, transcribeURL: storage.audioURL(for: name))
        state = .idle
    }

    /// Lanza una transcripción en segundo plano: crea el elemento placeholder y lo rellena al terminar.
    /// No toca `state` (solo el contador), así no interfiere con una grabación nueva en curso.
    @MainActor
    private func enqueueTranscription(audioFileName: String?, transcribeURL: URL) {
        let duration = AudioPlayer.duration(of: transcribeURL)
        let id = onVoiceNoteStarted?(audioFileName, duration)
        transcribeInBackground(id: id, url: transcribeURL)
    }

    /// Reintenta transcribir el audio de un elemento que ya existe (nota fallida con su audio).
    /// `forceProvider` ("openai") salta la elección y el fallback (p. ej. "Usar OpenAI esta vez").
    @MainActor
    func retry(itemID: UUID, audioFileName: String, forceProvider: String? = nil) {
        onVoiceNoteRetrying?(itemID)
        transcribeInBackground(id: itemID, url: storage.audioURL(for: audioFileName), forceProvider: forceProvider)
    }

    /// Núcleo de la transcripción en 2º plano (común a grabar, subir y reintentar). No toca `state`.
    @MainActor
    private func transcribeInBackground(id: UUID?, url: URL, forceProvider: String? = nil) {
        transcribingCount += 1
        // Resolver el modelo del proveedor activo aquí, en el MainActor (evita leer Settings.shared
        // desde el hilo de la transcripción). Gemini y OpenAI tienen su propio ajuste de modelo.
        let model = Settings.shared.aiProvider == "gemini"
            ? Settings.shared.geminiModel : Settings.shared.transcriptionModel
        let language = Settings.shared.transcriptionLanguage
        Task { @MainActor in
            defer { transcribingCount -= 1 }
            do {
                let text = try await AIProvider.transcribe(audioURL: url, language: language,
                                                           model: model, forceProvider: forceProvider)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { if let id { onVoiceNoteFailed?(id, nil) } }   // sin voz: no es error de clave
                else { if let id { onVoiceNoteTranscribed?(id, trimmed) } }
            } catch let e as TranscriptionError {
                if let id { onVoiceNoteFailed?(id, e) }   // el audio queda en el historial para reintentar/recuperar
            } catch {
                if let id { onVoiceNoteFailed?(id, TranscriptionError.wrap(error, provider: AIProvider.selected)) }
            }
        }
    }

    private func stopMeterTimer() { meterTimer?.invalidate(); meterTimer = nil }

    private static func normalized(power db: Float) -> Float {
        let minDb: Float = -50
        if db < minDb { return 0 }
        return min(1, (db - minDb) / -minDb)
    }

    nonisolated func audioRecorderDidFinishRecording(_ r: AVAudioRecorder, successfully ok: Bool) {
        Task { @MainActor in
            removeDeviceListener()   // garantiza quitar el listener también si el delegado se dispara solo
            finishing = false
            recorder = nil
            guard let name = currentFileName else { return }   // cancelado: no es error, solo salir
            currentFileName = nil
            guard ok else { state = .error("La grabación falló"); return }
            ingest(audioFileName: name)   // conserva el .m4a y transcribe
        }
    }

    deinit { removeDeviceListener() }   // red de seguridad (no toca @MainActor: solo CoreAudio + la var)
}
