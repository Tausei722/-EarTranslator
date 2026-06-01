import AVFoundation
import Combine

class TTSManager: NSObject, ObservableObject {
    @Published var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var speakGeneration = 0
    private let writeQueue = DispatchQueue(label: "tts.write", qos: .userInitiated)

    override init() {
        super.init()
        audioEngine.attach(playerNode)
    }

    /// pan: -1.0 = 左耳のみ, 0.0 = 両耳, 1.0 = 右耳のみ
    func speak(text: String, languageCode: String, pan: Float = 0.0) {
        synthesizer.stopSpeaking(at: .immediate)
        playerNode.stop()
        if audioEngine.isRunning { audioEngine.stop() }

        speakGeneration += 1
        let generation = speakGeneration

        playerNode.pan = pan
        DispatchQueue.main.async { self.isSpeaking = true }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0

        // write() はブロッキングなのでバックグラウンドで実行
        writeQueue.async { [weak self] in
            guard let self else { return }

            var engineStarted = false

            self.synthesizer.write(utterance) { [weak self] buffer in
                guard let self,
                      let pcmBuffer = buffer as? AVAudioPCMBuffer,
                      self.speakGeneration == generation else { return }

                if pcmBuffer.frameLength > 0 {
                    if !engineStarted {
                        engineStarted = true
                        // 実際のバッファフォーマットで接続（言語ごとに異なるため）
                        self.audioEngine.connect(
                            self.playerNode,
                            to: self.audioEngine.mainMixerNode,
                            format: pcmBuffer.format
                        )
                        try? self.audioEngine.start()
                    }
                    self.playerNode.scheduleBuffer(pcmBuffer)
                    if !self.playerNode.isPlaying { self.playerNode.play() }
                } else {
                    // 合成完了：再生しきったら isSpeaking を下げる
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
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        playerNode.stop()
        if audioEngine.isRunning { audioEngine.stop() }
        speakGeneration += 1
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}
