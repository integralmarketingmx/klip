import Foundation

/// Detects whether a text looks like a credential (API key, token, secret) for the mini manager.
enum CredentialDetector {
    private static let patterns: [String] = [
        "sk-[A-Za-z0-9_-]{20,}",                              // OpenAI
        "ghp_[A-Za-z0-9]{20,}", "github_pat_[A-Za-z0-9_]{20,}", "gho_[A-Za-z0-9]{20,}", // GitHub
        "xox[baprs]-[A-Za-z0-9-]{10,}",                        // Slack
        "AKIA[0-9A-Z]{16}",                                    // AWS
        "AIza[0-9A-Za-z_-]{30,}",                              // Google API
        "ya29\\.[0-9A-Za-z_-]+",                               // Google OAuth
        "eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{6,}", // JWT
        "(sk|rk|pk)_(live|test)_[A-Za-z0-9]{16,}", "whsec_[A-Za-z0-9]{16,}",  // Stripe
        "SG\\.[A-Za-z0-9_-]{16,}\\.[A-Za-z0-9_-]{16,}",        // SendGrid
        "SK[0-9a-fA-F]{32}", "AC[0-9a-fA-F]{32}",              // Twilio
        "(?i)npm_[A-Za-z0-9]{20,}",                            // npm token
        "glpat-[A-Za-z0-9_-]{20,}",                            // GitLab PAT
        "-----BEGIN [A-Z ]*PRIVATE KEY-----",                  // PEM private key
        "hf_[A-Za-z0-9]{20,}",                                 // Hugging Face
        "(?i)bearer\\s+[A-Za-z0-9._-]{20,}",                   // Bearer token
        "(?i)(api[_-]?key|secret|access[_-]?token|password|token)\\s*[:=]\\s*\"?[A-Za-z0-9._\\-+/]{12,}"
    ]

    static func looksLikeCredential(_ text: String) -> Bool {
        matchedSecret(in: text) != nil
    }

    /// The substring that matched a secret pattern, or nil. Scans LINE BY LINE so a secret inside a
    /// larger multi-line blob (e.g. a pasted .env, a config block, or a chat message with a token) is
    /// still caught — the previous `(newline && >=200 chars) → not a credential` rule let those through
    /// and showed them in cleartext. Only an upper byte cap remains, purely for performance.
    static func matchedSecret(in text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 12, t.count <= 20_000 else { return nil }
        for line in t.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.count >= 12 else { continue }
            for p in patterns {
                if let r = s.range(of: p, options: .regularExpression) { return String(s[r]) }
            }
        }
        return nil
    }

    /// Masked version to display without revealing the secret. For multi-line blobs we never echo the
    /// content (masking just the tail would hide a harmless trailing line, not the secret).
    static func masked(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.contains("\n") { return "🔑 ••••••" }
        guard t.count > 4 else { return "••••" }
        return "••••" + String(t.suffix(4))
    }
}
