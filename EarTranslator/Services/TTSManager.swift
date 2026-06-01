import AVFoundation
import Combine

class TTSManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var tempFileURL: URL?
    private var speakGeneration = 0
    private let writeQueue = DispatchQueue(label: "tts.write", qos: .userInitiated)

    func prepare() {}  // AVAudioPlayer はエンジン起動不要

    // MARK: - Public API

    /// pan: -1.0 = 左耳のみ, 0.0 = 両耳, 1.0 = 右耳のみ
    func speak(text: String, languageCode: String, pan: Float = 0.0) {
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()
        cleanupTempFile()
        speakGeneration += 1
        let generation = speakGeneration

        DispatchQueue.main.async { self.isSpeaking = true }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0

        // write() はブロッキングなのでバックグラウンドで実行
        writeQueue.async { [weak self] in
            guard let self, self.speakGeneration == generation else { return }

            // PCM バッファを収集
            var buffers: [AVAudioPCMBuffer] = []
            var format: AVAudioFormat?

            self.synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else { return }
                if format == nil { format = pcm.format }
                buffers.append(pcm)
            }

            guard self.speakGeneration == generation,
                  let fmt = format, !buffers.isEmpty else {
                DispatchQueue.main.async { [weak self] in self?.isSpeaking = false }
                return
            }

            // 一時 CAF ファイルに書き出す
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".caf")
            do {
                let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
                for buf in buffers { try file.write(from: buf) }
            } catch {
                DispatchQueue.main.async { [weak self] in self?.isSpeaking = false }
                return
            }

            // AVAudioPlayer で再生（pan 対応 ＋ iOS ルーティング自動追従）
            DispatchQueue.main.async { [weak self] in
                guard let self, self.speakGeneration == generation else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                do {
                    let p = try AVAudioPlayer(contentsOf: url)
                    p.pan = pan
                    p.delegate = self
                    p.prepareToPlay()
                    p.play()
                    self.player = p
                    self.tempFileURL = url
                } catch {
                    try? FileManager.default.removeItem(at: url)
                    self.isSpeaking = false
                }
            }
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()
        cleanupTempFile()
        speakGeneration += 1
        DispatchQueue.main.async { self.isSpeaking = false }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        cleanupTempFile()
        DispatchQueue.main.async { self.isSpeaking = false }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        cleanupTempFile()
        DispatchQueue.main.async { self.isSpeaking = false }
    }

    // MARK: - Private

    private func cleanupTempFile() {
        guard let url = tempFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        tempFileURL = nil
    }
}
