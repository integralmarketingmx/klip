import Foundation

/// Prueba e2e headless del código real (no copias). Se invoca con `--selftest` y SIEMPRE corre
/// contra un directorio aislado (`KLIP_DATA_DIR`) para no tocar el historial ni las API keys reales.
/// Ejercita los fixes de la auditoría: cifrado de claves (C3), Codable backward-compat (C7),
/// persistencia con reintento y prune de huérfanos (C6/B), e integridad de imágenes (C).
enum SelfTest {
    private static var passed = 0
    private static var failed = 0

    private static func check(_ name: String, _ cond: @autoclosure () -> Bool) {
        if cond() { passed += 1; print("  ✓ \(name)") }
        else { failed += 1; print("  ✗ \(name)   <-- FALLÓ") }
    }

    static func run() -> Bool {
        guard ProcessInfo.processInfo.environment["KLIP_DATA_DIR"]?.isEmpty == false else {
            print("ABORTADO: --selftest requiere KLIP_DATA_DIR (dir aislado) para no tocar datos reales.")
            return false
        }
        print("== Klip self-test (e2e sobre el código real) ==")

        testSecretStoreEncryption()
        testSecretStorePlaintextMigration()
        testClipboardItemBackwardCompat()
        testClipboardItemRoundTrip()
        testStoragePersistenceRoundTrip()
        testPruneOrphans()

        print("== Resultado: \(passed) ok, \(failed) fallo(s) ==")
        return failed == 0
    }

    // MARK: - C3: cifrado de API keys en disco

    private static func testSecretStoreEncryption() {
        print("[C3] Cifrado AES-256-GCM de API keys")
        let secret = "sk-test-ABCDEF1234567890"
        let ok = (try? SecretStore.set(secret, .openai)) ?? false
        check("set() confirma round-trip", ok)
        check("get() descifra al valor original", SecretStore.get(.openai) == secret)
        check("last4() correcto", SecretStore.last4(.openai) == "7890")

        // El archivo en disco debe estar cifrado: ni contiene el secreto ni es texto plano.
        let url = Storage.shared.baseURL.appendingPathComponent("openai.key")
        let onDisk = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        check("archivo en disco NO contiene el secreto en claro", !onDisk.contains(secret))
        check("archivo en disco lleva prefijo cifrado KENC1:", onDisk.hasPrefix("KENC1:"))
        SecretStore.delete(.openai)
        check("delete() borra la clave", SecretStore.get(.openai) == nil)
    }

    private static func testSecretStorePlaintextMigration() {
        print("[C3] Migración de clave en texto plano (versión anterior)")
        let legacy = "gemini-legacy-PLAINTEXT-9999"
        let url = Storage.shared.baseURL.appendingPathComponent("gemini.key")
        try? legacy.write(to: url, atomically: true, encoding: .utf8)   // simula archivo viejo en claro

        // get() debe devolver el valor y, de paso, re-cifrar el archivo en disco.
        let read = SecretStore.get(.gemini)
        check("get() lee la clave plana antigua", read == legacy)
        let onDisk = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        check("tras leerla, el archivo quedó re-cifrado", onDisk.hasPrefix("KENC1:"))
        check("la clave sigue descifrando al valor original", SecretStore.get(.gemini) == legacy)
        SecretStore.delete(.gemini)
    }

    // MARK: - C7: Codable backward-compatible (copyCount / firstSeenAt)

    private static func testClipboardItemBackwardCompat() {
        print("[C7] Decode de items.json antiguo (sin copyCount/firstSeenAt)")
        // JSON de un item de una versión anterior: NO trae copyCount ni firstSeenAt.
        let legacyJSON = """
        {"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","kind":"text","preview":"hola",
         "createdAt":"2025-01-01T00:00:00Z","pinned":false,"text":"hola"}
        """
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let item = try? dec.decode(ClipboardItem.self, from: Data(legacyJSON.utf8)) else {
            check("decodifica item antiguo sin error", false); return
        }
        check("decodifica item antiguo sin error", true)
        check("copyCount antiguo = 1 por defecto", item.copyCount == 1)
        check("firstSeenAt antiguo = nil", item.firstSeenAt == nil)
        check("texto preservado", item.text == "hola")
    }

    private static func testClipboardItemRoundTrip() {
        print("[C7] Round-trip de item nuevo con copyCount")
        var item = ClipboardItem(kind: .text, text: "abc", preview: "abc")
        item.copyCount = 3
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let data = try? enc.encode(item),
              let back = try? dec.decode(ClipboardItem.self, from: data) else {
            check("codifica+decodifica item nuevo", false); return
        }
        check("codifica+decodifica item nuevo", true)
        check("copyCount preservado (=3)", back.copyCount == 3)
        check("firstSeenAt no-nil en item nuevo", back.firstSeenAt != nil)
    }

    // MARK: - C6/B: persistencia (guardar/cargar con reintento)

    private static func testStoragePersistenceRoundTrip() {
        print("[C6] Persistencia saveItems → loadItems")
        let storage = Storage.shared
        let items = [
            ClipboardItem(kind: .text, text: "uno", preview: "uno"),
            ClipboardItem(kind: .text, text: "dos", preview: "dos", copyCount: 5),
        ]
        storage.saveItems(items)
        let loaded = storage.loadItems()
        check("guarda y recarga la misma cantidad", loaded.count == items.count)
        check("preserva el texto", loaded.first?.text == "uno")
        check("preserva copyCount tras recargar", loaded.first(where: { $0.text == "dos" })?.copyCount == 5)
        storage.saveItems([])   // limpiar para no contaminar los siguientes
    }

    // MARK: - C: prune de huérfanos (archivos sin item referenciado)

    private static func testPruneOrphans() {
        print("[C] pruneOrphans borra archivos no referenciados")
        let storage = Storage.shared
        let fm = FileManager.default
        let referenced = "ref-\(UUID().uuidString).png"
        let orphan = "orphan-\(UUID().uuidString).png"
        let refURL = storage.imagesURL.appendingPathComponent(referenced)
        let orphURL = storage.imagesURL.appendingPathComponent(orphan)
        try? Data("x".utf8).write(to: refURL)
        try? Data("x".utf8).write(to: orphURL)

        storage.pruneOrphans(referencedAudio: [], referencedImages: [referenced])
        check("conserva el archivo referenciado", fm.fileExists(atPath: refURL.path))
        check("borra el archivo huérfano", !fm.fileExists(atPath: orphURL.path))
        try? fm.removeItem(at: refURL)
    }
}
