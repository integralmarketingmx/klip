import Foundation
import AppKit

/// Interfaz de persistencia en disco que hoy cumple `Storage`.
///
/// Consejo C4 (Arquitectura): se extrae como protocolo para DESACOPLAR a los consumidores
/// (sobre todo `ClipboardManager` y `Recorder`) del singleton concreto `Storage.shared`,
/// habilitando inyección de dependencias y pruebas con un doble en memoria. NO cambia la
/// lógica: declara EXACTAMENTE los miembros que se consumen fuera de `Storage.swift`.
///
/// No es `@MainActor`: `Storage` es seguro para hilos (se usa desde el OCR en segundo plano y
/// desde la transcripción), así que el protocolo tampoco confina sus métodos al hilo principal.
protocol PersistentStoring: AnyObject {
    // MARK: Carpetas base (las leen SecretStore y SelfTest)
    var baseURL: URL { get }
    var imagesURL: URL { get }

    // MARK: Historial (metadatos)
    func loadItems() -> [ClipboardItem]
    func saveItems(_ items: [ClipboardItem])

    // MARK: Imágenes
    @discardableResult
    func saveImage(_ image: NSImage, fileName: String) -> URL?
    func imageURL(for fileName: String) -> URL
    func loadImage(fileName: String) -> NSImage?
    func deleteImage(fileName: String)
    func cachedImage(fileName: String) -> NSImage?
    func memoryCachedImage(fileName: String) -> NSImage?
    func pngData(from image: NSImage) -> Data?

    // MARK: Audio (notas de voz)
    func audioURL(for fileName: String) -> URL
    func deleteAudio(fileName: String)
    func audioExists(fileName: String) -> Bool
    func protectAudio(fileName: String)
    func importAudio(from url: URL) -> String?

    // MARK: Mantenimiento
    func pruneOrphans(referencedAudio: Set<String>, referencedImages: Set<String>)

    // MARK: Copia de seguridad / exportación
    func exportBackup(to dest: URL) throws
    func importBackup(from src: URL) throws -> [ClipboardItem]
    func combinedPDF(from items: [ClipboardItem]) -> (data: Data, exported: Int)?
    func zipExportableCount(_ items: [ClipboardItem]) -> Int
    func exportItemsZip(_ items: [ClipboardItem], to dest: URL) throws
}
