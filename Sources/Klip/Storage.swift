import Foundation
import AppKit

/// Persistencia en disco: metadatos del historial (JSON), imágenes (PNG) y audio temporal (m4a).
final class Storage {
    static let shared = Storage()

    let baseURL: URL
    let imagesURL: URL
    let audioBaseURL: URL
    private let itemsURL: URL

    init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")

        let newBase = appSupport.appendingPathComponent("Klip", isDirectory: true)
        let oldBase = appSupport.appendingPathComponent("PastaClip", isDirectory: true)

        // Migración: si existe la carpeta vieja y aún no la nueva, mover entera (rename atómico).
        if fm.fileExists(atPath: oldBase.path), !fm.fileExists(atPath: newBase.path) {
            do { try fm.moveItem(at: oldBase, to: newBase) }
            catch { try? fm.copyItem(at: oldBase, to: newBase) }
        }

        baseURL = newBase
        imagesURL = baseURL.appendingPathComponent("images", isDirectory: true)
        audioBaseURL = baseURL.appendingPathComponent("audio", isDirectory: true)
        itemsURL = baseURL.appendingPathComponent("items.json")
        try? fm.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: audioBaseURL, withIntermediateDirectories: true)
        // Igual que items.json (0600): el store contiene datos personales (texto, voz, imágenes).
        Self.restrict(baseURL.path, 0o700)
        Self.restrict(imagesURL.path, 0o700)
        Self.restrict(audioBaseURL.path, 0o700)
    }

    /// Restringe un archivo/carpeta al propietario (privacidad consistente con items.json).
    static func restrict(_ path: String, _ perms: Int) {
        try? FileManager.default.setAttributes([.posixPermissions: perms], ofItemAtPath: path)
    }

    // MARK: - Historial (metadatos)

    func loadItems() -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: itemsURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let items = try? decoder.decode([ClipboardItem].self, from: data) { return items }
        // Decodificación falló pero el archivo existe → respaldarlo antes de que algo lo sobrescriba.
        if !data.isEmpty {
            try? data.write(to: baseURL.appendingPathComponent("items.corrupt.json"), options: .atomic)
        }
        return []
    }

    func saveItems(_ items: [ClipboardItem]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: itemsURL, options: .atomic)
        // El historial puede contener credenciales en texto: restringir a solo el usuario.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: itemsURL.path)
    }

    // MARK: - Imágenes

    @discardableResult
    func saveImage(_ image: NSImage, fileName: String) -> URL? {
        guard let png = pngData(from: image) else { return nil }
        let url = imagesURL.appendingPathComponent(fileName)
        do {
            try png.write(to: url, options: .atomic)
            Self.restrict(url.path, 0o600)
            return url
        } catch { return nil }
    }

    func imageURL(for fileName: String) -> URL { imagesURL.appendingPathComponent(fileName) }
    func loadImage(fileName: String) -> NSImage? { NSImage(contentsOf: imageURL(for: fileName)) }
    func deleteImage(fileName: String) {
        imageCache.removeObject(forKey: fileName as NSString)
        try? FileManager.default.removeItem(at: imageURL(for: fileName))
    }

    private let imageCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>(); c.countLimit = 60; return c
    }()

    /// Imagen cacheada en memoria: evita releer/decodificar del disco en cada render de la lista.
    func cachedImage(fileName: String) -> NSImage? {
        if let c = imageCache.object(forKey: fileName as NSString) { return c }
        guard let img = loadImage(fileName: fileName) else { return nil }
        imageCache.setObject(img, forKey: fileName as NSString)
        return img
    }

    func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Audio (notas de voz: se conserva el original junto a la transcripción)

    func audioURL(for fileName: String) -> URL { audioBaseURL.appendingPathComponent(fileName) }
    func deleteAudio(fileName: String) { try? FileManager.default.removeItem(at: audioURL(for: fileName)) }
    func audioExists(fileName: String) -> Bool { FileManager.default.fileExists(atPath: audioURL(for: fileName).path) }

    /// Restringe a 0600 un audio de nota de voz (lo crea AVAudioRecorder con el umask por defecto).
    func protectAudio(fileName: String) { Self.restrict(audioURL(for: fileName).path, 0o600) }

    /// Copia un audio externo (subido por el usuario) a nuestro almacén y devuelve el nombre nuevo,
    /// para poder reproducirlo y conservarlo aunque el archivo original se mueva o borre.
    func importAudio(from url: URL) -> String? {
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        let name = "\(UUID().uuidString).\(ext)"
        let dest = audioURL(for: name)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            Self.restrict(dest.path, 0o600)
            return name
        } catch { return nil }
    }

    /// Borra archivos de audio/imágenes que ya no referencia ningún elemento (huérfanos por crash, etc.).
    func pruneOrphans(referencedAudio: Set<String>, referencedImages: Set<String>) {
        prune(dir: audioBaseURL, keep: referencedAudio)
        prune(dir: imagesURL, keep: referencedImages)
    }

    private func prune(dir: URL, keep: Set<String>) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names where !keep.contains(name) {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    // MARK: - Copia de seguridad (exportar / importar)

    /// Exporta el historial (items.json + imágenes + audio) a un .zip. NO incluye las API keys.
    func exportBackup(to dest: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("KlipExport-\(UUID().uuidString)", isDirectory: true)
        let stage = work.appendingPathComponent("Klip", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        if fm.fileExists(atPath: itemsURL.path) {
            try fm.copyItem(at: itemsURL, to: stage.appendingPathComponent("items.json"))
        }
        if fm.fileExists(atPath: imagesURL.path) {
            try fm.copyItem(at: imagesURL, to: stage.appendingPathComponent("images"))
        }
        if fm.fileExists(atPath: audioBaseURL.path) {
            try fm.copyItem(at: audioBaseURL, to: stage.appendingPathComponent("audio"))
        }
        try? fm.removeItem(at: dest)
        try Self.runDitto(["-c", "-k", "--keepParent", stage.path, dest.path])
    }

    /// Importa una copia .zip y REEMPLAZA el historial actual. Devuelve los elementos cargados.
    func importBackup(from src: URL) throws -> [ClipboardItem] {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("KlipImport-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        try Self.runDitto(["-x", "-k", src.path, tmp.path])

        guard let root = Self.findBackupRoot(in: tmp) else {
            throw NSError(domain: "Klip", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "El archivo no es una copia de seguridad de Klip (falta items.json)."])
        }
        // Reemplazar items.json
        try? fm.removeItem(at: itemsURL)
        try fm.copyItem(at: root.appendingPathComponent("items.json"), to: itemsURL)
        Self.restrict(itemsURL.path, 0o600)
        // Reemplazar carpetas de medios
        replaceDir(imagesURL, from: root.appendingPathComponent("images"))
        replaceDir(audioBaseURL, from: root.appendingPathComponent("audio"))
        imageCache.removeAllObjects()
        return loadItems()
    }

    private func replaceDir(_ target: URL, from source: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: target)
        if fm.fileExists(atPath: source.path) { try? fm.copyItem(at: source, to: target) }
        else { try? fm.createDirectory(at: target, withIntermediateDirectories: true) }
        Self.restrict(target.path, 0o700)
    }

    /// Localiza la carpeta del backup que contiene items.json (keepParent → .../Klip/items.json).
    private static func findBackupRoot(in dir: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.appendingPathComponent("items.json").path) { return dir }
        guard let subs = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        for sub in subs where (try? sub.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            if fm.fileExists(atPath: sub.appendingPathComponent("items.json").path) { return sub }
        }
        return nil
    }

    private static func runDitto(_ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "Klip", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "No se pudo comprimir/descomprimir (ditto \(p.terminationStatus))."])
        }
    }
}
