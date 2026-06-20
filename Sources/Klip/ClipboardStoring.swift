import Foundation
import AppKit

/// Interfaz pública que `ClipboardManager` expone a las vistas y controladores.
///
/// Consejo C4 (Arquitectura): protocolo para DESACOPLAR a `PanelController`, `AppDelegate` y las
/// vistas del tipo concreto `ClipboardManager`, habilitando pruebas con un doble. NO cambia la
/// lógica: lista EXACTAMENTE los miembros que se consumen fuera de `ClipboardManager.swift`.
///
/// `@MainActor` porque `ClipboardManager` ya lo es (Consejo C2): el estado del historial vive en
/// el hilo principal. Las vistas SwiftUI siguen tomando el tipo concreto vía `@ObservedObject`
/// (un protocolo no puede observarse); este protocolo es para inyección y atestaciones.
@MainActor
protocol ClipboardStoring: AnyObject {
    /// Historial publicado (solo lectura para los consumidores).
    var items: [ClipboardItem] { get }
    /// Nombres de colecciones existentes (para los filtros).
    var collections: [String] { get }

    // MARK: Ciclo de vida del monitor
    func start()
    func pauseMonitoring()
    func resumeMonitoring()
    func applyMaxItems()

    // MARK: Acciones sobre el portapapeles
    func copyToPasteboard(_ item: ClipboardItem)
    func setClipboardText(_ text: String)
    func copyCapturedToClipboard(_ image: NSImage)

    // MARK: Mutaciones del historial
    func delete(_ item: ClipboardItem)
    func clearAll()
    @discardableResult
    func clearSince(_ cutoff: Date) -> Int
    func countSince(_ cutoff: Date) -> Int
    func reload(_ newItems: [ClipboardItem])
    func togglePin(_ item: ClipboardItem)
    func toggleCredential(_ item: ClipboardItem)
    func rename(_ item: ClipboardItem, to name: String)
    func assignCollection(_ ids: Set<UUID>, to name: String?)

    // MARK: Capturas e imágenes generadas por la app
    func addCapturedImage(_ image: NSImage, name: String?)
    @discardableResult
    func addAnnotatedScreenshot(_ image: NSImage, copyToClipboard: Bool) -> UUID?

    // MARK: OCR
    nonisolated func extractText(from item: ClipboardItem) -> String?
    func setOCRText(_ text: String, for id: UUID)

    // MARK: Notas de voz (callbacks desde Recorder)
    @discardableResult
    func beginVoiceNote(audioFileName: String?, duration: Double?) -> UUID
    func finishVoiceNote(id: UUID, text: String)
    func failVoiceNote(id: UUID, reason: String?)
    func markVoiceNoteTranscribing(id: UUID)
}
