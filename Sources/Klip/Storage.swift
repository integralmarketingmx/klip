import Foundation
import AppKit
import PDFKit

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
        // Si la imagen ya tiene un bitmap, codificar PNG directo desde el rep de mayor resolución
        // (evita el round-trip por TIFF, que duplica memoria con capturas grandes).
        if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { $0.pixelsWide < $1.pixelsWide }),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
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

    /// Importa una copia .zip y REEMPLAZA el historial actual, de forma **transaccional**:
    /// valida el backup, mueve lo actual a `.importbak`, copia lo nuevo y, ante CUALQUIER fallo,
    /// restaura desde el respaldo → nunca se pierde el historial existente. Devuelve los elementos.
    /// (Pesado: ejecútalo fuera del hilo principal.)
    func importBackup(from src: URL) throws -> [ClipboardItem] {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("KlipImport-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        try Self.runDitto(["-x", "-k", src.path, tmp.path])

        guard let root = Self.findBackupRoot(in: tmp) else {
            throw Self.err("El archivo no es una copia de seguridad de Klip (falta items.json).")
        }
        // Validar que el items.json del backup decodifica ANTES de tocar nada (no importar basura).
        let newItemsFile = root.appendingPathComponent("items.json")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: newItemsFile),
              let decoded = try? decoder.decode([ClipboardItem].self, from: data) else {
            throw Self.err("La copia de seguridad está dañada (items.json ilegible).")
        }

        let newImages = root.appendingPathComponent("images")
        let newAudio = root.appendingPathComponent("audio")
        // Respaldos con nombre único por intento → un residuo de un import abortado nunca colisiona
        // con el moveItem de abajo (evita restaurar un .bak rancio sobre el original intacto).
        let token = UUID().uuidString
        let bakItems = baseURL.appendingPathComponent("items.json.\(token).importbak")
        let bakImages = baseURL.appendingPathComponent("images.\(token).importbak")
        let bakAudio = baseURL.appendingPathComponent("audio.\(token).importbak")
        // Limpiar residuos de imports abortados anteriores (no colisionan con los de este intento).
        if let leftovers = try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) {
            for f in leftovers where f.lastPathComponent.hasSuffix(".importbak") { try? fm.removeItem(at: f) }
        }

        // Restaura un destino desde su respaldo (solo si el respaldo existe → original a salvo).
        func restore(_ live: URL, _ bak: URL) {
            guard fm.fileExists(atPath: bak.path) else { return }   // sin bak: el live es el original intacto
            try? fm.removeItem(at: live)
            try? fm.moveItem(at: bak, to: live)
        }

        do {
            // Mover lo actual a .bak (renames atómicos en el mismo volumen).
            if fm.fileExists(atPath: itemsURL.path)     { try fm.moveItem(at: itemsURL, to: bakItems) }
            if fm.fileExists(atPath: imagesURL.path)    { try fm.moveItem(at: imagesURL, to: bakImages) }
            if fm.fileExists(atPath: audioBaseURL.path) { try fm.moveItem(at: audioBaseURL, to: bakAudio) }
            // Colocar lo nuevo.
            try fm.copyItem(at: newItemsFile, to: itemsURL)
            if fm.fileExists(atPath: newImages.path) { try fm.copyItem(at: newImages, to: imagesURL) }
            else { try fm.createDirectory(at: imagesURL, withIntermediateDirectories: true) }
            if fm.fileExists(atPath: newAudio.path) { try fm.copyItem(at: newAudio, to: audioBaseURL) }
            else { try fm.createDirectory(at: audioBaseURL, withIntermediateDirectories: true) }
        } catch {
            restore(itemsURL, bakItems)        // rollback: deja el historial como estaba
            restore(imagesURL, bakImages)
            restore(audioBaseURL, bakAudio)
            throw error
        }

        [bakItems, bakImages, bakAudio].forEach { try? fm.removeItem(at: $0) }   // éxito: limpiar respaldos
        Self.restrict(itemsURL.path, 0o600)
        Self.restrict(imagesURL.path, 0o700)
        Self.restrict(audioBaseURL.path, 0o700)
        imageCache.removeAllObjects()
        return decoded
    }

    private static func err(_ msg: String) -> NSError {
        NSError(domain: "Klip", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
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

    // MARK: - Combinar / exportar selección (vibe coders)

    /// Combina varios elementos en un PDF (una página por elemento): imágenes como página de imagen,
    /// textos como página de texto. Para subir varias capturas/notas de una sola vez a una IA.
    /// Devuelve los datos y cuántas páginas se generaron (puede ser menos que items.count si algún
    /// elemento no tenía contenido exportable). nil si no se pudo generar ninguna página.
    func combinedPDF(from items: [ClipboardItem]) -> (data: Data, exported: Int)? {
        let doc = PDFDocument()
        var idx = 0
        for it in items {
            var pageImage: NSImage?
            if it.kind == .image, let f = it.imageFileName { pageImage = loadImage(fileName: f) }
            else if let t = it.text, !t.isEmpty { pageImage = Self.pageImage(forText: t) }
            if let img = pageImage, let page = PDFPage(image: img) { doc.insert(page, at: idx); idx += 1 }
        }
        guard idx > 0, let data = doc.dataRepresentation() else { return nil }
        return (data, idx)
    }

    /// Renderiza un texto en una "página" (imagen tamaño carta) con márgenes, para incrustar en el PDF.
    /// Usa un drawingHandler (seguro fuera del hilo principal) en vez de lockFocus, ya que combinedPDF
    /// se ejecuta en una cola de fondo.
    private static func pageImage(forText text: String) -> NSImage {
        let pageW: CGFloat = 612, margin: CGFloat = 40   // US Letter a 72 dpi
        let style = NSMutableParagraphStyle(); style.lineSpacing = 3
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.black, .paragraphStyle: style]
        let textW = pageW - margin * 2
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: textW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        let pageH = max(200, ceil(bounds.height) + margin * 2)
        return NSImage(size: NSSize(width: pageW, height: pageH), flipped: false) { _ in
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: pageW, height: pageH).fill()
            (text as NSString).draw(with: NSRect(x: margin, y: margin, width: textW, height: pageH - margin * 2),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
            return true
        }
    }

    /// Cuántos de los elementos tienen contenido que exportar a ZIP (imagen en disco, audio, o texto).
    func zipExportableCount(_ items: [ClipboardItem]) -> Int {
        let fm = FileManager.default
        return items.reduce(0) { acc, it in
            if it.kind == .image, let f = it.imageFileName, fm.fileExists(atPath: imageURL(for: f).path) { return acc + 1 }
            if let af = it.audioFileName, audioExists(fileName: af) { return acc + 1 }
            if let t = it.text, !t.isEmpty { return acc + 1 }
            return acc
        }
    }

    /// Exporta los elementos seleccionados a un .zip (imágenes PNG, textos .txt, audios). Para subir el lote junto.
    func exportItemsZip(_ items: [ClipboardItem], to dest: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("KlipSel-\(UUID().uuidString)", isDirectory: true)
        let stage = work.appendingPathComponent("Klip", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        for (i, it) in items.enumerated() {
            let n = String(format: "%02d", i + 1)
            let base = (it.name?.isEmpty == false ? it.name! : "item").replacingOccurrences(of: "/", with: "-")
            if it.kind == .image, let f = it.imageFileName, fm.fileExists(atPath: imageURL(for: f).path) {
                try? fm.copyItem(at: imageURL(for: f), to: stage.appendingPathComponent("\(n)-\(base).png"))
            } else if let af = it.audioFileName, audioExists(fileName: af) {
                try? fm.copyItem(at: audioURL(for: af), to: stage.appendingPathComponent("\(n)-\(base).m4a"))
                if let t = it.text, !t.isEmpty { try? t.data(using: .utf8)?.write(to: stage.appendingPathComponent("\(n)-\(base).txt")) }
            } else if let t = it.text, !t.isEmpty {
                try? t.data(using: .utf8)?.write(to: stage.appendingPathComponent("\(n)-\(base).txt"))
            }
        }
        try? fm.removeItem(at: dest)
        try Self.runDitto(["-c", "-k", "--keepParent", stage.path, dest.path])
    }
}

extension NSImage {
    /// Dimensiones REALES en píxeles (no en puntos): toma el rep de mayor resolución. En pantallas
    /// retina, `size` viene en puntos (la mitad), así que esto es lo que el usuario espera ver.
    var pixelDimensions: NSSize {
        var w = 0, h = 0
        for r in representations { w = max(w, r.pixelsWide); h = max(h, r.pixelsHigh) }
        return (w > 0 && h > 0) ? NSSize(width: w, height: h) : size
    }
}
