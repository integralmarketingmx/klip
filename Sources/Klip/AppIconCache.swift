import AppKit

/// Caché en memoria de iconos de apps por bundle ID, para mostrar el origen sin coste por frame.
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]
    private static let lock = NSLock()   // el caché puede consultarse desde varios hilos (thumbnails async)

    static func icon(forBundleID id: String?) -> NSImage? {
        guard let id, !id.isEmpty else { return nil }
        lock.lock()
        let cached = cache[id]
        lock.unlock()
        if let cached { return cached }
        // La resolución (lenta) va FUERA del lock; a lo sumo dos hilos calculan el mismo icono.
        let ws = NSWorkspace.shared
        guard let url = ws.urlForApplication(withBundleIdentifier: id) else { return nil }
        let img = ws.icon(forFile: url.path)
        lock.lock()
        cache[id] = img
        lock.unlock()
        return img
    }
}
