import SwiftUI

/// UI del popup dedicado de grabación de voz (separado del panel del historial).
struct RecordingView: View {
    @ObservedObject var recorder: Recorder
    var onStop: () -> Void
    var onCancel: () -> Void
    var onClose: () -> Void
    var onOpenPreferences: () -> Void

    var body: some View {
        VStack(spacing: 16) { content }
            .frame(width: 360, height: 320)
            .onChange(of: recorder.state) { _, s in
                if case .idle = s { onClose() }
            }
    }

    @ViewBuilder private var content: some View {
        switch recorder.state {
        case .recording:
            if recorder.silenceWarning {
                VStack(spacing: 12) {
                    Image(systemName: "moon.zzz.fill").font(.system(size: 34)).foregroundStyle(.orange)
                    Text("¿Sigues ahí?").font(.headline)
                    Text("Sin voz por 2 min. Si sigue el silencio, se finaliza sola.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Continuar grabando") { recorder.continueRecording() }
                        .keyboardShortcut(.defaultAction)
                    HStack(spacing: 12) {
                        Button("Cancelar", action: onCancel).keyboardShortcut(.cancelAction)
                        Button("Detener y transcribir", action: onStop)
                    }
                }.padding()
            } else {
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Circle().fill(.red).frame(width: 11, height: 11)
                            .opacity(recorder.level > 0.12 ? 1 : 0.5)
                        Text("Grabando nota de voz").font(.headline)
                    }
                    Text(timeString(recorder.duration))
                        .font(.system(size: 32, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                    levelBars
                    HStack(spacing: 12) {
                        Button(action: onCancel) { Label("Cancelar", systemImage: "xmark") }
                            .keyboardShortcut(.cancelAction)
                        Button(action: onStop) {
                            Label("Detener y transcribir", systemImage: "stop.fill")
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                    }
                }.padding()
            }

        case .missingAPIKey:
            VStack(spacing: 12) {
                Image(systemName: "key.slash").font(.system(size: 34)).foregroundStyle(.orange)
                Text("Falta tu API key de OpenAI").font(.headline)
                Text("Añádela en Preferencias para transcribir voz.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack {
                    Button("Cerrar") { recorder.reset() }
                    Button("Abrir Preferencias") { onOpenPreferences(); recorder.reset() }
                        .buttonStyle(.borderedProminent)
                }
            }.padding()

        case .error(let m):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 34)).foregroundStyle(.orange)
                Text("Error").font(.headline)
                Text(m).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3)
                Button("Cerrar") { recorder.reset() }.buttonStyle(.borderedProminent)
            }.padding()

        case .idle:
            Color.clear
        }
    }

    private var levelBars: some View {
        let active = Int((recorder.level * 18).rounded())
        return HStack(spacing: 3) {
            ForEach(0..<18, id: \.self) { i in
                Capsule()
                    .fill(i < active ? Color.accentColor : Color.primary.opacity(0.15))
                    .frame(width: 4, height: i < active ? 10 + CGFloat((i % 4) * 6) : 6)
            }
        }
        .frame(height: 34)
        .animation(.linear(duration: 0.1), value: recorder.level)
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
