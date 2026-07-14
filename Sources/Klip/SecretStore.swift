import Foundation
import CryptoKit
import IOKit

/// Almacén local de la API key, en un archivo del directorio de soporte de la app.
///
/// Las claves se guardan CIFRADAS en disco con AES-256-GCM (CryptoKit). La llave simétrica
/// deriva (HKDF-SHA256) de un valor estable de la máquina (IOPlatformUUID; con respaldo a un
/// secreto persistido 0600) más una sal fija. Es protección "en reposo": elimina el texto plano,
/// pero NO equivale al Llavero ni a una firma Developer ID — un atacante con acceso a este Mac y
/// al mismo usuario podría re-derivar la llave. Aun así, evita que la clave quede legible a simple
/// vista en el archivo.
///
/// Se usa un archivo (perms 0600) en lugar del Llavero porque, con firma **ad-hoc**,
/// macOS vuelve a pedir permiso del Llavero en cada recompilación (la identidad cambia),
/// lo que rompía la transcripción.
enum SecretStore {
    /// Cada proveedor guarda su clave en un archivo distinto (0600) del directorio de la app.
    /// - smtp: contraseña SMTP del usuario (método de envío "SMTP").
    /// - googleOAuth: refresh token del usuario (método "Iniciar sesión con Google").
    enum Key: String {
        case openai = "openai.key"
        case gemini = "gemini.key"
        case smtp = "smtp.pass"
        case googleOAuth = "google.refresh"
    }

    /// Prefijo que marca un archivo como cifrado por nosotros (formato v1). Lo que NO empiece con
    /// este prefijo se trata como texto plano de una versión anterior y se migra al primer `set`.
    private static let encPrefix = "KENC1:"

    private static func fileURL(_ k: Key) -> URL {
        Storage.shared.baseURL.appendingPathComponent(k.rawValue)
    }

    static func get(_ k: Key = .openai) -> String? {
        guard let raw = try? String(contentsOf: fileURL(k), encoding: .utf8) else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        if s.hasPrefix(encPrefix) {
            guard let plain = decrypt(s) else { return nil }
            let t = plain.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        // Texto plano (versión anterior): devolverlo tal cual y re-cifrarlo en disco (migración).
        try? writeEncrypted(s, k)
        return s
    }

    /// Guarda la clave (CIFRADA) y CONFIRMA leyéndola de vuelta. Devuelve `true` solo si el archivo
    /// quedó escrito con exactamente el valor esperado. Propaga el error real si la escritura falla
    /// (p. ej. permisos del directorio), en vez de tragárselo con `try?`.
    @discardableResult
    static func set(_ value: String, _ k: Key = .openai) throws -> Bool {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        try writeEncrypted(t, k)
        // Confirmación: releer (y descifrar) del disco y comparar.
        return get(k) == t
    }

    /// Cifra `plain` con AES-256-GCM y lo escribe (0600) con el prefijo de formato. Lanza si falla.
    private static func writeEncrypted(_ plain: String, _ k: Key) throws {
        let url = fileURL(k)
        // Asegurar que el directorio base existe (Storage lo crea, pero no de más).
        try? FileManager.default.createDirectory(at: Storage.shared.baseURL,
                                                 withIntermediateDirectories: true)
        let sealed = try AES.GCM.seal(Data(plain.utf8), using: symmetricKey())
        guard let combined = sealed.combined else { throw SecretStoreError.encryptFailed }
        let payload = encPrefix + combined.base64EncodedString()
        try payload.write(to: url, atomically: true, encoding: .utf8)   // sin try?: que el error suba
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Descifra un payload con nuestro prefijo. Devuelve nil si el formato o la llave no coinciden.
    private static func decrypt(_ payload: String) -> String? {
        let b64 = String(payload.dropFirst(encPrefix.count))
        guard let combined = Data(base64Encoded: b64),
              let box = try? AES.GCM.SealedBox(combined: combined),
              let plain = try? AES.GCM.open(box, using: symmetricKey()) else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    static func delete(_ k: Key = .openai) { try? FileManager.default.removeItem(at: fileURL(k)) }

    static func hasKey(_ k: Key = .openai) -> Bool { get(k) != nil }

    static func last4(_ k: Key = .openai) -> String? {
        guard let v = get(k), v.count >= 4 else { return nil }
        return String(v.suffix(4))
    }

    // MARK: - Derivación de la llave simétrica

    private enum SecretStoreError: Error { case encryptFailed }

    /// Sal fija de la app (no es secreta: solo separa el dominio de derivación).
    private static let salt = Data("KlipSecretStore.v1.salt".utf8)

    /// Deriva la llave AES-256 (HKDF-SHA256) a partir de un valor estable de la máquina.
    private static func symmetricKey() -> SymmetricKey {
        let material = Data(machineSeed().utf8)
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: material),
                                      salt: salt,
                                      info: Data("Klip.apiKeys".utf8),
                                      outputByteCount: 32)
    }

    /// Semilla estable de esta máquina. Fuente preferida: IOPlatformUUID. Respaldo: secreto
    /// aleatorio persistido. CLAVE: la fuente se FIJA en el primer uso (marcador `.machine.src`)
    /// y nunca cambia, para no romper el descifrado de secretos ya guardados si el UUID aparece/
    /// desaparece entre ejecuciones. Migración-segura: instalaciones previas sin marcador que ya
    /// usaban la semilla persistida (existe `.machine.seed`) la conservan; las demás usan el UUID.
    private static func machineSeed() -> String {
        let markerURL = Storage.shared.baseURL.appendingPathComponent(".machine.src")
        let seedURL = Storage.shared.baseURL.appendingPathComponent(".machine.seed")
        let uuid = platformUUID().flatMap { $0.isEmpty ? nil : $0 }
        let recorded = try? String(contentsOf: markerURL, encoding: .utf8)

        func record(_ src: String) {
            try? src.write(to: markerURL, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: markerURL.path)
        }

        switch recorded {
        case "seed":
            return persistedSeed()                       // fuente ya fijada al respaldo
        case "uuid":
            // No generamos una semilla nueva si el UUID desaparece: eso cambiaría la llave.
            // Si falta, devolvemos sentinela estable → el descifrado falla limpio y el usuario
            // re-ingresa; al volver el UUID, todo vuelve a descifrar.
            return uuid ?? ""
        default:
            // Primer uso (o instalación previa sin marcador).
            if FileManager.default.fileExists(atPath: seedURL.path) {
                record("seed"); return persistedSeed()   // ya venía usando el respaldo: conservarlo
            }
            if let uuid { record("uuid"); return uuid }
            record("seed"); return persistedSeed()
        }
    }

    private static func platformUUID() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/")
        guard entry != MACH_PORT_NULL else { return nil }
        defer { IOObjectRelease(entry) }
        guard let cf = IORegistryEntryCreateCFProperty(entry, "IOPlatformUUID" as CFString,
                                                       kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
        return cf as? String
    }

    /// Respaldo: secreto aleatorio generado una vez y guardado 0600 (solo si IOPlatformUUID falla).
    private static func persistedSeed() -> String {
        let url = Storage.shared.baseURL.appendingPathComponent(".machine.seed")
        if let s = try? String(contentsOf: url, encoding: .utf8), !s.isEmpty { return s }
        let fresh = UUID().uuidString + UUID().uuidString
        try? fresh.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return fresh
    }
}
