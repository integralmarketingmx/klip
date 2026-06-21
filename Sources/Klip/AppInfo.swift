import Foundation

/// Metadatos de la app para "Acerca de" y enlaces.
enum AppInfo {
    static let name = "Klip"
    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.4"
    }
    static let repoURL = "https://github.com/tamibot/klip"
    static let issuesURL = "https://github.com/tamibot/klip/issues"
}
