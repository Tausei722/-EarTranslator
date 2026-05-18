import Speech
import AVFoundation
import Combine

class SpeechRecognitionManager: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

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
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        DispatchQueue.main.async { self.isRecording = true }
    }

    @discardableResult
    func stopRecording() -> String {
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
}
