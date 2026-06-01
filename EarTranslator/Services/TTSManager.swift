import AVFoundation
import Combine

class TTSManager: NSObject, ObservableObject {
    @Published var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var connectionFormat: AVAudioFormat?
    private var speakGeneration = 0
    private let writeQueue = DispatchQueue(label: "tts.write", qos: .userInitiated)

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    /// AudioSessionManager.configure() の直後に呼ぶ
    func prepare() {
        setupEngine()
    }

    // MARK: - Engine Setup

    private func setupEngine() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.attach(playerNode)

        // ハードウェア出力フォーマットで固定接続
        // → 言語ごとにフォーマットが変わっても接続を変えない（クラッシュ防止）
        // → iOS が決めたフォーマットなので音声ルートにも正しく乗る
        let hwFormat = audioEngine.outputNode.outputFormat(forBus: 0)
        connectionFormat = hwFormat
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: hwFormat)

        try? audioEngine.start()
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        // イヤホン接続・切断時にエンジンを再構築して新ルートに接続
        DispatchQueue.main.async { [weak self] in
            self?.setupEngine()
        }
    }

    // MARK: - Public API

    /// pan: -1.0 = 左耳のみ, 0.0 = 両耳, 1.0 = 右耳のみ
    func speak(text: String, languageCode: String, pan: Float = 0.0) {
        synthesizer.stopSpeaking(at: .immediate)
        playerNode.stop()
        speakGeneration += 1
        let generation = speakGeneration

        playerNode.pan = pan
        DispatchQueue.main.async { self.isSpeaking = true }

        if !audioEngine.isRunning { try? audioEngine.start() }

        guard let targetFormat = connectionFormat else {
            DispatchQueue.main.async { self.isSpeaking = false }
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0

        writeQueue.async { [weak self] in
            guard let self else { return }

            self.synthesizer.write(utterance) { [weak self] buffer in
                guard let self,
                      let pcmBuffer = buffer as? AVAudioPCMBuffer,
                      self.speakGeneration == generation else { return }

                if pcmBuffer.frameLength > 0 {
                    // TTS の出力フォーマット → ハードウェアフォーマットに変換してスケジュール
                    if let converted = self.convert(pcmBuffer, to: targetFormat) {
                        self.playerNode.scheduleBuffer(converted)
                        if !self.playerNode.isPlaying { self.playerNode.play() }
                    }
                } else {
                    // 合成完了：再生しきったら isSpeaking を下げる
                    guard let sentinel = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 1) else {
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
        speakGeneration += 1
        DispatchQueue.main.async { self.isSpeaking = false }
    }

    // MARK: - Format Conversion

    private func convert(_ input: AVAudioPCMBuffer, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        if input.format == target { return input }
        guard let converter = AVAudioConverter(from: input.format, to: target) else { return nil }

        let ratio = target.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        var provided = false
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            guard !provided else { status.pointee = .noDataNow; return nil }
            provided = true
            status.pointee = .haveData
            return input
        }

        var error: NSError?
        converter.convert(to: output, error: &error, withInputFrom: inputBlock)
        return error == nil ? output : nil
    }
}
