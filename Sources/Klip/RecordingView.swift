import SwiftUI

/// UI del popup dedicado de grabación de voz (separado del panel del historial).
struct RecordingView: View {
    @ObservedObject var recorder: Recorder
    @ObservedObject var settings = Settings.shared
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
                    Text(L10n.t("rec.stillthere")).font(.headline)
                    Text(L10n.t("rec.silenceWarning"))
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button(L10n.t("rec.continueRecording")) { recorder.continueRecording() }
                        .keyboardShortcut(.defaultAction)
                    HStack(spacing: 12) {
                        Button(L10n.t("common.cancel"), action: onCancel).keyboardShortcut(.cancelAction)
                        Button(L10n.t("rec.stop"), action: onStop)
                    }
                }.padding()
            } else {
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Circle().fill(.red).frame(width: 11, height: 11)
                            .opacity(recorder.level > 0.12 ? 1 : 0.5)
                        Text(L10n.t("rec.recording")).font(.headline)
                    }
                    Text(timeString(recorder.duration))
                        .font(.system(size: 32, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                    levelBars
                    HStack(spacing: 12) {
                        Button(action: onCancel) { Label(L10n.t("common.cancel"), systemImage: "xmark") }
                            .keyboardShortcut(.cancelAction)
                        Button(action: onStop) {
                            Label(L10n.t("rec.stop"), systemImage: "stop.fill")
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                    }
                }.padding()
            }

        case .missingAPIKey:
            VStack(spacing: 12) {
                Image(systemName: "key.slash").font(.system(size: 34)).foregroundStyle(.orange)
                Text(L10n.t("rec.missingKey.title")).font(.headline)
                Text(L10n.t("rec.missingKey.body"))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack {
                    Button(L10n.t("common.close")) { recorder.reset() }
                    Button(L10n.t("common.openPrefs")) { onOpenPreferences(); recorder.reset() }
                        .buttonStyle(.borderedProminent)
                }
            }.padding()

        case .error(let m):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 34)).foregroundStyle(.orange)
                Text(L10n.t("common.error")).font(.headline)
                Text(m).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3)
                Button(L10n.t("common.close")) { recorder.reset() }.buttonStyle(.borderedProminent)
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
