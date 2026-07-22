import SwiftUI
import AppKit

/// Guía de uso: atajos de Klip + atajos de captura de macOS + cómo usar.
struct GuideView: View {
    @ObservedObject var settings = Settings.shared

    private struct Row: Identifiable { let id = UUID(); let keys: String; let what: String }

    private var klipShortcuts: [Row] {
        [
            Row(keys: settings.combo.displayString, what: L10n.t("guide.k.toggle")),
            Row(keys: settings.voiceCombo.displayString, what: L10n.t("guide.k.voice")),
            Row(keys: "↑ ↓", what: L10n.t("guide.k.move")),
            Row(keys: "↩", what: L10n.t("guide.k.choose")),
            Row(keys: "⌘1 … ⌘9", what: L10n.t("guide.k.direct")),
            Row(keys: "Esc", what: L10n.t("guide.k.close")),
            Row(keys: "⌘,", what: L10n.t("guide.k.prefs"))
        ]
    }

    private var macShortcuts: [Row] {
        [
            Row(keys: "⌘⇧3", what: L10n.t("guide.m.full")),
            Row(keys: "⌘⇧4", what: L10n.t("guide.m.area")),
            Row(keys: "⌘⇧5", what: L10n.t("guide.m.tools")),
            Row(keys: "⌘⇧⌃4", what: L10n.t("guide.m.clip"))
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                section(L10n.t("guide.sec.klip"), klipShortcuts)
                section(L10n.t("guide.sec.mac"), macShortcuts,
                        footer: L10n.t("guide.mac.footer"))

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("guide.howto")).font(.headline)
                    bullet(L10n.t("guide.b1"))
                    bullet(String(format: L10n.t("guide.b2"), settings.combo.displayString))
                    bullet(L10n.t("guide.b3"))
                    bullet(L10n.t("guide.b4"))
                }
            }
            .padding(20)
        }
        .frame(width: 460, height: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let logo = HistoryView.appLogo {
                Image(nsImage: logo).resizable().frame(width: 48, height: 48)
            }
            VStack(alignment: .leading) {
                Text(L10n.t("win.guide")).font(.title2).bold()
                Text("v\(AppInfo.version)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func section(_ title: String, _ rows: [Row], footer: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ForEach(rows) { r in
                HStack(alignment: .top, spacing: 12) {
                    Text(r.keys)
                        .font(.system(.body, design: .monospaced)).bold()
                        .frame(width: 90, alignment: .leading)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                    Text(r.what).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let footer { Text(footer).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(.secondary)
            Text(text).font(.system(size: 13))
        }
    }
}
