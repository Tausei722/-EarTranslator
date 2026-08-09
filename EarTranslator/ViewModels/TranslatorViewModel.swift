import Foundation
import Combine

struct LanguagePair: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let langA: Language
    let langB: Language

    struct Language: Hashable {
        let name: String
        let locale: String      // SFSpeechRecognizer
        let ttsCode: String     // AVSpeechSynthesisVoice
        let translateCode: String // ML Kit TranslateLanguage rawValue
    }
}

let availablePairs: [LanguagePair] = [
    LanguagePair(
        name: "日本語 ↔ English",
        langA: .init(name: "日本語", locale: "ja-JP", ttsCode: "ja-JP", translateCode: "ja"),
        langB: .init(name: "English", locale: "en-US", ttsCode: "en-US", translateCode: "en")
    ),
]

@MainActor
class TranslatorViewModel: ObservableObject {
    // MARK: - Published
    @Published var selectedPair: LanguagePair = availablePairs[0]

    @Published var transcriptA = ""
    @Published var translationA = ""
    @Published var transcriptB = ""
    @Published var translationB = ""

    @Published var isRecordingA = false
    @Published var isRecordingB = false
    @Published var isSpeaking = false
    @Published var isTranslating = false
    @Published var errorMessage: String?

    // MARK: - Internal
    private var lastResultA: (text: String, code: String) = ("", "")
    private var lastResultB: (text: String, code: String) = ("", "")

    private let speechManager = SpeechRecognitionManager()
    private let ttsManager = TTSManager()
    private let translationService = TranslationService()
    private var cancellables = Set<AnyCancellable>()

    enum Speaker { case none, a, b }

    // MARK: - Setup

    func setup() async {
        try? AudioSessionManager.shared.configure()
        ttsManager.prepare()
        let granted = await speechManager.requestAuthorization()
        if !granted { errorMessage = "マイクと音声認識の権限が必要です" }

        speechManager.$transcript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self else { return }
                switch self.activeSpeaker {
                case .a: self.transcriptA = text
                case .b: self.transcriptB = text
                case .none: break
                }
            }
            .store(in: &cancellables)

        speechManager.onSilenceDetected = { [weak self] in
            guard let self else { return }
            self.stopRecording(speaker: self.activeSpeaker)
        }

        ttsManager.$isSpeaking
            .receive(on: DispatchQueue.main)
            .assign(to: &$isSpeaking)
    }

    // MARK: - Recording

    private var activeSpeaker: Speaker = .none

    func startRecording(speaker: Speaker) {
        guard !isRecordingA, !isRecordingB else { return }
        ttsManager.stop()
        activeSpeaker = speaker

        let locale = speaker == .a
            ? Locale(identifier: selectedPair.langA.locale)
            : Locale(identifier: selectedPair.langB.locale)

        do {
            try speechManager.startRecording(locale: locale)
            switch speaker {
            case .a: isRecordingA = true; transcriptA = ""; translationA = ""
            case .b: isRecordingB = true; transcriptB = ""; translationB = ""
            case .none: break
            }
        } catch {
            errorMessage = "録音エラー: \(error.localizedDescription)"
        }
    }

    func stopRecording(speaker: Speaker) {
        let text = speechManager.stopRecording()
        switch speaker {
        case .a: isRecordingA = false
        case .b: isRecordingB = false
        case .none: return
        }
        guard !text.isEmpty else { return }
        Task { await performTranslation(text: text, speaker: speaker) }
    }

    // MARK: - Replay

    func replay(speaker: Speaker) {
        guard !isRecordingA, !isRecordingB else { return }
        switch speaker {
        case .a:
            guard !lastResultA.text.isEmpty else { return }
            ttsManager.speak(text: lastResultA.text, languageCode: lastResultA.code)
        case .b:
            guard !lastResultB.text.isEmpty else { return }
            ttsManager.speak(text: lastResultB.text, languageCode: lastResultB.code)
        case .none: break
        }
    }

    // MARK: - Translation (ML Kit)

    private func performTranslation(text: String, speaker: Speaker) async {
        let fromCode = speaker == .a ? selectedPair.langA.translateCode : selectedPair.langB.translateCode
        let toCode   = speaker == .a ? selectedPair.langB.translateCode : selectedPair.langA.translateCode
        let ttsCode  = speaker == .a ? selectedPair.langB.ttsCode       : selectedPair.langA.ttsCode

        isTranslating = true
        defer { isTranslating = false }

        do {
            let result = try await translationService.translate(text: text, from: fromCode, to: toCode)

            switch speaker {
            case .a:
                translationA = result
                lastResultA = (result, ttsCode)
            case .b:
                translationB = result
                lastResultB = (result, ttsCode)
            case .none: break
            }
            ttsManager.speak(text: result, languageCode: ttsCode)
        } catch {
            errorMessage = "翻訳エラー: \(error.localizedDescription)"
        }
    }
}
