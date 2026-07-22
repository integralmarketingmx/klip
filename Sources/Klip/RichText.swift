import AppKit

/// Turns rich clipboard text (RTF/HTML, e.g. an AI chat answer on a dark theme) into CLEAN Markdown:
/// bold → **…**, italic → *…*, emojis kept as-is, while colors, background and fonts are dropped. This is
/// what "always paste clean" stores, so a clip pastes without dragging styling but keeps its bold/italic.
enum RichText {
    /// Clean Markdown for the pasteboard's rich text, or nil if it carries no usable rich text.
    static func cleanMarkdown(from pb: NSPasteboard) -> String? {
        // Parsing rich text runs synchronously on the capture (poll/main) thread; a multi-MB blob can take
        // seconds and freeze the UI. Cap it — over the limit, fall back to the plain string instantly.
        let limit = 256_000
        let rtf = pb.data(forType: .rtf) ?? pb.data(forType: NSPasteboard.PasteboardType("public.rtf"))
        if let rtf, rtf.count < limit, let attr = try? NSAttributedString(
            data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            return markdown(from: attr)
        }
        if let html = pb.data(forType: .html), html.count < limit, let attr = try? NSAttributedString(
            data: html, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) {
            return markdown(from: attr)
        }
        return nil
    }

    private struct Span { var text: String; var bold: Bool; var italic: Bool }

    private static func markdown(from attr: NSAttributedString) -> String {
        let ns = attr.string as NSString
        guard ns.length > 0 else { return "" }
        // Merge consecutive characters that share the same (bold, italic), ignoring colour/background/font,
        // so adjacent runs don't produce doubled markers like **a****b**.
        var spans: [Span] = []
        attr.enumerateAttribute(.font, in: NSRange(location: 0, length: attr.length), options: []) { value, range, _ in
            var bold = false, italic = false
            if let font = value as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                bold = traits.contains(.bold)
                italic = traits.contains(.italic)
            }
            // Slice on the String (grapheme-safe) so a run boundary can't split an emoji's surrogate pair.
            let text = Range(range, in: attr.string).map { String(attr.string[$0]) } ?? ns.substring(with: range)
            if var last = spans.last, last.bold == bold, last.italic == italic {
                last.text += text; spans[spans.count - 1] = last
            } else {
                spans.append(Span(text: text, bold: bold, italic: italic))
            }
        }
        var out = ""
        for s in spans {
            let trimmed = s.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, s.bold || s.italic else { out += s.text; continue }
            // Keep surrounding whitespace OUTSIDE the markers (WhatsApp/Markdown ignore "* x *").
            // Must include \n/\t, not just spaces: AppKit tucks a block element's trailing newline
            // INSIDE the bold run (a heading's "Heading\n"), so a spaces-only restore would drop it
            // and glue the heading to the next line ("**Heading**Body").
            let lead = String(s.text.prefix(while: { $0.isWhitespace }))
            let trail = String(s.text.reversed().prefix(while: { $0.isWhitespace }).reversed())
            let marker = s.bold && s.italic ? "***" : (s.bold ? "**" : "*")
            out += lead + marker + trimmed + marker + trail
        }
        // Los adjuntos inline (imágenes) llegan como U+FFFC en .string: fuera — pegados en destino
        // se ven como cajas vacías o corrompen el texto.
        return out.replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
