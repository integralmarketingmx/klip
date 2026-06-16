import Foundation
import AVFoundation

/// Reproductor sencillo para escuchar las notas de voz guardadas (una a la vez).
/// `playingFileName` permite a la UI mostrar el botón ▶/⏹ del elemento que suena.
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayer()

    @Published private(set) var playingFileName: String?
    private var player: AVAudioPlayer?

    func isPlaying(_ fileName: String) -> Bool { playingFileName == fileName }

    /// Alterna: si ya suena ese archivo, lo detiene; si no, lo reproduce (deteniendo cualquier otro).
    func toggle(fileName: String) {
        if playingFileName == fileName { stop() } else { play(fileName: fileName) }
    }

    func play(fileName: String) {
        stop()
        let url = Storage.shared.audioURL(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.delegate = self
        guard p.play() else { return }
        player = p
        playingFileName = fileName
    }

    func stop() {
        player?.stop()
        player = nil
        if playingFileName != nil { playingFileName = nil }
    }

    /// Detiene solo si justo está sonando ese archivo (p. ej. al eliminarlo del historial).
    func stopIfPlaying(_ fileName: String) {
        if playingFileName == fileName { stop() }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        clear(if: player)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        clear(if: player)
    }

    /// Limpia solo si el que terminó sigue siendo el reproductor actual (evita cortar una reproducción nueva).
    private func clear(if finished: AVAudioPlayer) {
        DispatchQueue.main.async { [weak self] in
            guard let self, finished === self.player else { return }
            self.player = nil
            self.playingFileName = nil
        }
    }
}
