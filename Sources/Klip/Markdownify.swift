import Foundation

/// Local (offline) conversion of text to Markdown.
enum Markdownify {
    static func fromText(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }

        // URL on its own? → link.
        if t.range(of: "^https?://\\S+$", options: .regularExpression) != nil {
            return "[\(t)](\(t))"
        }
        // Looks like code? → fenced block (with a best-effort language tag).
        if looksLikeCode(t) {
            return "```\(inferCodeLanguage(t))\n\(text)\n```"
        }
        // Normal text → paragraphs separated by a blank line.
        let paras = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return paras.joined(separator: "\n\n")
    }

    static func looksLikeCode(_ s: String) -> Bool {
        let keywords = ["func ", "var ", "let ", "import ", "class ", "struct ",
                        "def ", "function ", "const ", "#include", "public ", "private ",
                        "=>", "</", "/>", "});"]
        if keywords.contains(where: { s.contains($0) }) { return true }
        let codeChars = Set("{};=<>()[]")
        let symbolCount = s.filter { codeChars.contains($0) }.count
        return s.count > 0 && Double(symbolCount) / Double(s.count) > 0.06
    }

    /// Best-effort language tag for a fenced code block (cheap heuristics). Returns "" when unsure —
    /// a wrong/empty tag still renders fine, it just helps the AI/editor highlight when we're confident.
    static func inferCodeLanguage(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = t.lowercased()
        if (t.hasPrefix("{") || t.hasPrefix("[")), t.contains("\""), t.contains(":") { return "json" }
        if t.hasPrefix("#!"), lower.contains("sh") { return "bash" }
        // Keywords anchored to line start so a word in prose ("git is great") doesn't trigger a tag.
        if t.range(of: "(?m)^\\s*(\\$ |sudo |npm |yarn |pnpm |brew |curl |cd |git (clone|pull|push|commit|checkout|switch|status|add|rebase|merge|log|diff|branch|stash|fetch|reset|init|remote|tag) )", options: .regularExpression) != nil { return "bash" }
        if t.hasPrefix("<") { return (lower.contains("<!doctype html") || lower.contains("<html")) ? "html" : "xml" }
        // SQL only when UPPERCASE keywords pair up (SELECT…FROM), so prose "select the file from…" doesn't match.
        if t.range(of: "\\b(SELECT\\b[\\s\\S]+\\bFROM\\b|INSERT INTO\\b|UPDATE\\b[\\s\\S]+\\bSET\\b|DELETE FROM\\b|CREATE TABLE\\b)", options: .regularExpression) != nil { return "sql" }
        if t.contains("func ") || t.range(of: "@(MainActor|objc|State|Published|IBOutlet|escaping)", options: .regularExpression) != nil
            || t.range(of: "(?m)^\\s*(import \\w+$|guard .+ else \\{)", options: .regularExpression) != nil { return "swift" }
        if t.range(of: "(?m)^\\s*(def |class \\w+.*:|from \\w[\\w.]* import |import \\w)", options: .regularExpression) != nil { return "python" }
        if t.range(of: "=>", options: .regularExpression) != nil
            || t.range(of: "(?m)^\\s*(function |const |let |var |export )", options: .regularExpression) != nil
            || t.contains("require(") { return "javascript" }
        return ""
    }
}

/// Exports the entire history as a Markdown document.
enum MarkdownExporter {
    static func history(_ items: [ClipboardItem]) -> String {
        var out = "# Klip — Historial del portapapeles\n\n"
        let df = DateFormatter()
        df.locale = Locale(identifier: "es")
        df.dateFormat = "yyyy-MM-dd HH:mm"

        for item in items {
            let time = df.string(from: item.createdAt)
            var meta = time
            if item.isRemote == true { meta += " · Otro dispositivo" }
            else if let s = item.sourceName { meta += " · \(s)" }
            if item.isVoiceNote == true { meta += " · 🎙 Nota de voz" }
            out += "## \(meta)\n\n"

            switch item.kind {
            case .text:
                if item.isCredential == true {
                    // Don't export secrets in the clear: masked only.
                    out += "🔑 _Credencial oculta (\(CredentialDetector.masked(item.text ?? "")))_\n\n"
                } else {
                    out += Markdownify.fromText(item.text ?? "") + "\n\n"
                }
            case .image:
                out += "![imagen](images/\(item.imageFileName ?? "imagen.png"))\n\n"
            }
        }
        return out
    }
}
