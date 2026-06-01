import Speech
import AVFoundation
import Combine

class SpeechRecognitionManager: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false

    var onSilenceDetected: (() -> Void)?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var silenceTimer: Timer?
    private var hasSpeechStarted = false
    private let silenceThreshold: Float = 0.01  // RMSレベルのしきい値
    private let silenceDuration: TimeInterval = 1.5  // 無音が続いたら停止するまでの秒数

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startRecording(locale: Locale) throws {
        stopRecording()
        transcript = ""
        hasSpeechStarted = false

        speechRecognizer = SFSpeechRecognizer(locale: locale)
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false

        let inputNode = audioEngine.inputNode

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, _ in
            guard let self, let result else { return }
            DispatchQueue.main.async {
                self.transcript = result.bestTranscription.formattedString
            }
        }

        let fmt = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buffer, _ in
            recognitionRequest.append(buffer)
            self?.checkSilence(buffer: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        DispatchQueue.main.async { self.isRecording = true }
    }

    @discardableResult
    func stopRecording() -> String {
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioEngine.stop()
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        DispatchQueue.main.async { self.isRecording = false }
        return transcript
    }

    // MARK: - Silence Detection

    private func checkSilence(buffer: AVAudioPCMBuffer) {
        let rms = calculateRMS(buffer: buffer)

        if rms >= silenceThreshold {
            // 発話を検出 → 無音タイマーをリセット
            hasSpeechStarted = true
            DispatchQueue.main.async {
                self.silenceTimer?.invalidate()
                self.silenceTimer = nil
            }
        } else if hasSpeechStarted {
            // 発話後の無音 → タイマーがなければセット
            DispatchQueue.main.async {
                guard self.silenceTimer == nil else { return }
                self.silenceTimer = Timer.scheduledTimer(
                    withTimeInterval: self.silenceDuration,
                    repeats: false
                ) { [weak self] _ in
                    self?.silenceTimer = nil
                    self?.onSilenceDetected?()
                }
            }
        }
    }

    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var sum: Float = 0
        for ch in 0..<channelCount {
            for i in 0..<frameLength {
                sum += channelData[ch][i] * channelData[ch][i]
            }
        }
        return sqrt(sum / Float(channelCount * frameLength))
    }
}
