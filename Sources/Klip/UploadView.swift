import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Ventana para subir audios y transcribirlos: zona de arrastre + elegir archivos.
struct UploadView: View {
    @ObservedObject var recorder: Recorder
    var onChoose: () -> Void
    var onFiles: ([URL]) -> Void
    var onClose: () -> Void
    var onOpenPreferences: () -> Void

    @State private var hovering = false

    private let exts = ["m4a", "mp3", "wav", "mp4", "aac", "aiff", "flac", "ogg", "webm", "mpga", "mpeg", "m4b"]

    var body: some View {
        VStack(spacing: 14) {
            switch recorder.state {
            case .missingAPIKey:
                Image(systemName: "key.slash").font(.system(size: 34)).foregroundStyle(.orange)
                Text("Falta tu API key de OpenAI").font(.headline)
                HStack {
                    Button("Cerrar") { onClose() }
                    Button("Abrir Preferencias") { onOpenPreferences(); onClose() }.buttonStyle(.borderedProminent)
                }
            case .error(let m):
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 34)).foregroundStyle(.orange)
                Text(m).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Cerrar") { recorder.reset(); onClose() }
            default:
                Text("Subir audio para transcribir").font(.headline)
                dropZone
                Text("Se transcriben en segundo plano y aparecen en el historial.\nFormatos: m4a, mp3, wav, mp4, flac…")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Cerrar") { onClose() }
            }
        }
        .frame(width: 380, height: 300).padding()
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc.fill").font(.system(size: 38))
                .foregroundStyle(hovering ? Color.accentColor : .secondary)
            Text("Arrastra tus audios aquí").font(.system(size: 14, weight: .medium))
            Text("o").font(.caption).foregroundStyle(.secondary)
            Button("Elegir archivos…") { onChoose() }
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
                // loadItem entrega su callback en una cola interna arbitraria y los providers corren en
                // paralelo: acumular en main serializa los append (Array no es thread-safe).
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
