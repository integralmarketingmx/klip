import Foundation

/// Activa/desactiva atajos de captura nativos de macOS (symbolic hotkeys) para que Klip
/// pueda reclamarlos. ⌘⇧4 ("guardar área como archivo") es el symbolic hotkey id 30.
/// Mientras macOS lo tenga activo, intercepta la tecla antes que cualquier app.
enum SystemShortcuts {
    /// id 30 = ⌘⇧4 (área a archivo). Parámetros estándar de macOS: char '4'(52), keycode 21, ⌘⇧(1179648).
    private static let areaToFileID = 30
    private static let areaToFileParams = "52, 21, 1179648"

    /// Habilita o deshabilita el ⌘⇧4 del sistema. Deshabilitarlo lo libera para Klip.
    static func setMacScreenshotAreaEnabled(_ enabled: Bool) {
        let entry = "{ enabled = \(enabled ? 1 : 0); value = { parameters = (\(areaToFileParams)); type = standard; }; }"
        run("/usr/bin/defaults",
            ["write", "com.apple.symbolichotkeys", "AppleSymbolicHotKeys", "-dict-add", "\(areaToFileID)", entry])
        // Aplica el cambio sin necesidad de cerrar sesión.
        run("/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings", ["-u"])
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus }
        catch { return -1 }
    }
}
