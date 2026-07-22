import Foundation

/// Delivery method for the Klip-only Email feature. The matching @Published storage lives as an
/// additive block in Settings (Settings.swift, "Klip Email/OAuth/Upload" MARK) so SwiftUI can bind
/// to it with `$settings.mailMethod`. Kept isolated so the whole feature is easy to drop.
enum MailMethod: String, CaseIterable, Identifiable {
    /// Google Workspace: per-user desktop OAuth (scope gmail.send). Each person authorizes their own
    /// account and sends only as themselves — no key that could impersonate others in the domain.
    case oauth
    case smtp        // Manual SMTP: your own host/port/user/password.
    case systemMail  // System Mail: opens the native composer (NSSharingService) with the image.

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oauth:      return "Google Workspace"
        case .smtp:       return "SMTP"
        case .systemMail: return L10n.t("mail.method.system")
        }
    }
}
