import AVFoundation
import Combine

class TTSManager: NSObject, ObservableObject {
    @Published var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var speakGeneration = 0

    override init() {
        super.init()
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: nil)
    }

    /// pan: -1.0 = 左耳のみ, 0.0 = 両耳, 1.0 = 右耳のみ
    func speak(text: String, languageCode: String, pan: Float = 0.0) {
        synthesizer.stopSpeaking(at: .immediate)
        playerNode.stop()
        speakGeneration += 1
        let generation = speakGeneration

        playerNode.pan = pan
        DispatchQueue.main.async { self.isSpeaking = true }

        if !audioEngine.isRunning {
            try? audioEngine.start()
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0

        synthesizer.write(utterance) { [weak self] buffer in
            guard let self, let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

            if pcmBuffer.frameLength > 0 {
                self.playerNode.scheduleBuffer(pcmBuffer)
                if !self.playerNode.isPlaying { self.playerNode.play() }
            } else {
                // 空バッファ = 合成完了 → 再生しきったタイミングで isSpeaking を下げる
                guard let sentinel = AVAudioPCMBuffer(pcmFormat: pcmBuffer.format, frameCapacity: 1) else {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.speakGeneration == generation else { return }
                        self.isSpeaking = false
                    }
                    return
                }
                sentinel.frameLength = 1
                self.playerNode.scheduleBuffer(sentinel, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self, self.speakGeneration == generation else { return }
                        self.isSpeaking = false
                    }
                }
            }
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        playerNode.stop()
        speakGeneration += 1
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}
