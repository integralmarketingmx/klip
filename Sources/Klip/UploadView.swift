import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Window to upload audio files and transcribe them: drop zone + file picker.
struct UploadView: View {
    @ObservedObject var recorder: Recorder
    @ObservedObject var settings = Settings.shared   // re-localize live when the UI language changes
    var onChoose: () -> Void
    var onFiles: ([URL]) -> Void
    var onClose: () -> Void
    var onOpenPreferences: () -> Void

    @State private var hovering = false

    private let exts = ["m4a", "mp3", "wav", "mp4", "aac", "aiff", "flac", "ogg", "oga", "opus",
                        "webm", "mpga", "mpeg", "m4b"]

    var body: some View {
        VStack(spacing: 14) {
            switch recorder.state {
            case .missingAPIKey:
                Image(systemName: "key.slash").font(.system(size: 34)).foregroundStyle(.orange)
                Text(L10n.t("rec.nokey.title")).font(.headline)
                HStack {
                    Button(L10n.t("common.close")) { onClose() }
                    Button(L10n.t("rec.openprefs")) { onOpenPreferences(); onClose() }.buttonStyle(.borderedProminent)
                }
            case .error(let m):
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 34)).foregroundStyle(.orange)
                Text(m).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(L10n.t("common.close")) { recorder.reset(); onClose() }
            default:
                Text(L10n.t("upload.title")).font(.headline)
                dropZone
                Text(L10n.t("upload.info"))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if recorder.transcribingCount > 0 {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text(String(format: L10n.t(recorder.transcribingCount == 1 ? "upload.transcribing.one" : "upload.transcribing.many"), recorder.transcribingCount))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                }
                Button(L10n.t("common.close")) { onClose() }
            }
        }
        .frame(width: 380, height: 330).padding()
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc.fill").font(.system(size: 38))
                .foregroundStyle(hovering ? Color.accentColor : .secondary)
            Text(L10n.t("upload.drop")).font(.system(size: 14, weight: .medium))
            Text(L10n.t("upload.or")).font(.caption).foregroundStyle(.secondary)
            Button(L10n.t("upload.choose")) { onChoose() }
        }
        .frame(maxWidth: .infinity).frame(height: 150)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(hovering ? 0.12 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .foregroundStyle(hovering ? Color.accentColor : Color.secondary.opacity(0.5)))
        .onDrop(of: [UTType.fileURL], isTargeted: $hovering) { providers in
            handleDrop(providers); return true
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                // loadItem delivers its callback on an arbitrary internal queue and the providers run in
                // parallel: accumulating on main serializes the appends (Array is not thread-safe).
                let resolved: URL? = (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                    ?? (item as? URL)
                DispatchQueue.main.async {
                    if let resolved { urls.append(resolved) }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            let audio = urls.filter { exts.contains($0.pathExtension.lowercased()) }
            if !audio.isEmpty { onFiles(audio) }
        }
    }
}
