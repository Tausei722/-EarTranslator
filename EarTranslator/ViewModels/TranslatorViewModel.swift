import Foundation
import Combine
import Translation

struct LanguagePair: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let langA: Language
    let langB: Language

    struct Language: Hashable {
        let name: String
        let locale: String      // SFSpeechRecognizer
        let ttsCode: String     // AVSpeechSynthesisVoice
        let translateCode: String // Apple Translation / Locale.Language
    }
}

let availablePairs: [LanguagePair] = [
    LanguagePair(
        name: "日本語 ↔ English",
        langA: .init(name: "日本語", locale: "ja-JP", ttsCode: "ja-JP", translateCode: "ja"),
        langB: .init(name: "English", locale: "en-US", ttsCode: "en-US", translateCode: "en")
    ),
    LanguagePair(
        name: "日本語 ↔ 中文",
        langA: .init(name: "日本語", locale: "ja-JP", ttsCode: "ja-JP", translateCode: "ja"),
        langB: .init(name: "中文", locale: "zh-CN", ttsCode: "zh-CN", translateCode: "zh-Hans")
    ),
    LanguagePair(
        name: "日本語 ↔ 한국어",
        langA: .init(name: "日本語", locale: "ja-JP", ttsCode: "ja-JP", translateCode: "ja"),
        langB: .init(name: "한국어", locale: "ko-KR", ttsCode: "ko-KR", translateCode: "ko")
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

    // translationTask モディファイア用 — nil → 値 の変化でタスクを再トリガー
    @Published var translationConfig: TranslationSession.Configuration?

    // MARK: - Internal
    private(set) var pendingText = ""
    private(set) var pendingSpeaker: Speaker = .none
    private(set) var pendingTTSCode = ""

    private let speechManager = SpeechRecognitionManager()
    private let ttsManager = TTSManager()
    private var cancellables = Set<AnyCancellable>()

    enum Speaker { case none, a, b }

    // MARK: - Setup

    func setup() async {
        try? AudioSessionManager.shared.configure()
        let granted = await speechManager.requestAuthorization()
        if !granted { errorMessage = "マイクと音声認識の権限が必要です" }

        speechManager.$transcript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self else { return }
                switch self.pendingSpeaker {
                case .a: self.transcriptA = text
                case .b: self.transcriptB = text
                case .none: break
                }
            }
            .store(in: &cancellables)

        ttsManager.$isSpeaking
            .receive(on: DispatchQueue.main)
            .assign(to: &$isSpeaking)
    }

    // MARK: - Recording

    func startRecording(speaker: Speaker) {
        guard !isRecordingA, !isRecordingB else { return }
        ttsManager.stop()
        pendingSpeaker = speaker

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
        requestTranslation(text: text, speaker: speaker)
    }

    // MARK: - Translation Trigger

    private func requestTranslation(text: String, speaker: Speaker) {
        let fromCode = speaker == .a ? selectedPair.langA.translateCode : selectedPair.langB.translateCode
        let toCode   = speaker == .a ? selectedPair.langB.translateCode : selectedPair.langA.translateCode
        let ttsCode  = speaker == .a ? selectedPair.langB.ttsCode       : selectedPair.langA.ttsCode

        pendingText    = text
        pendingSpeaker = speaker
        pendingTTSCode = ttsCode
        isTranslating  = true

        // nil → 値 の変化で ContentView の .translationTask を再トリガー
        translationConfig = nil
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.translationConfig = TranslationSession.Configuration(
                source: Locale.Language(identifier: fromCode),
                target: Locale.Language(identifier: toCode)
            )
        }
    }

    // MARK: - Translation Execution（ContentView の .translationTask から呼ぶ）

    func performTranslation(session: TranslationSession) async {
        defer { isTranslating = false }
        let text    = pendingText
        let speaker = pendingSpeaker
        let ttsCode = pendingTTSCode

        guard !text.isEmpty else { return }

        do {
            let response = try await session.translate(text)
            let result = response.targetText

            switch speaker {
            case .a: translationA = result
            case .b: translationB = result
            case .none: break
            }
            ttsManager.speak(text: result, languageCode: ttsCode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
