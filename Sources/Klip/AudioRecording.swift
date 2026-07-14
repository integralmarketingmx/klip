import Foundation

/// Interfaz de grabación de notas de voz que `Recorder` expone a `PanelController` y a las vistas.
///
/// Consejo C4 (Arquitectura): protocolo para DESACOPLAR a `PanelController` y a las vistas de
/// grabación/subida del tipo concreto `Recorder`, habilitando pruebas con un doble. NO cambia la
/// lógica: declara EXACTAMENTE los miembros que se consumen fuera de `Recorder.swift`.
///
/// `@MainActor` porque `Recorder` ya lo es (Consejo C2): el estado de grabación vive en el hilo
/// principal. Las vistas SwiftUI siguen tomando el tipo concreto vía `@ObservedObject`; este
/// protocolo es para inyección y atestaciones.
@MainActor
protocol AudioRecording: AnyObject {
    // MARK: Estado publicado
    var state: RecorderState { get }
    var duration: TimeInterval { get }
    var level: Float { get }
    var silenceWarning: Bool { get }
    var transcribingCount: Int { get }
    /// true mientras hay (o se pidió) una grabación en curso; bloquea iniciar otra.
    var isRecording: Bool { get }

    // MARK: Control de la grabación
    func start()
    func stop()
    func cancel()
    func reset()
    func continueRecording()

    // MARK: Subida y reintento de transcripciones
    func transcribeFiles(_ urls: [URL])
    func retry(itemID: UUID, audioFileName: String, forceProvider: String?)

    // MARK: Callbacks hacia el historial (los conecta PanelController)
    /// El audio ya está guardado: crea el elemento (placeholder) y devuelve su id.
    var onVoiceNoteStarted: ((String?, Double?) -> UUID?)? { get set }
    /// Rellena la transcripción en el elemento ya creado.
    var onVoiceNoteTranscribed: ((UUID, String) -> Void)? { get set }
    /// La transcripción falló o no hubo voz: el elemento conserva el audio.
    var onVoiceNoteFailed: ((UUID, TranscriptionError?) -> Void)? { get set }
    /// Reintento: marca un elemento existente como "Transcribiendo…" otra vez.
    var onVoiceNoteRetrying: ((UUID) -> Void)? { get set }
}
