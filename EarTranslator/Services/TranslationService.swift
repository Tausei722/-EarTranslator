import Foundation
import MLKitTranslate

class TranslationService {
    private var translator: Translator?
    private var currentFrom = ""
    private var currentTo = ""

    func translate(text: String, from: String, to: String) async throws -> String {
        if from != currentFrom || to != currentTo {
            translator = nil
            let options = TranslatorOptions(
                sourceLanguage: TranslateLanguage(rawValue: from),
                targetLanguage: TranslateLanguage(rawValue: to)
            )
            translator = Translator.translator(options: options)
            currentFrom = from
            currentTo = to
            // 初回のみモデルをダウンロード（以降はオフライン動作）
            try await downloadModelIfNeeded()
        }
        guard let translator else { throw TranslationError.notInitialized }
        return try await withCheckedThrowingContinuation { cont in
            translator.translate(text) { result, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: result ?? "")
                }
            }
        }
    }

    private func downloadModelIfNeeded() async throws {
        guard let translator else { return }
        let conditions = ModelDownloadConditions(
            allowsCellularAccess: true,
            allowsBackgroundDownloading: true
        )
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            translator.downloadModelIfNeeded(with: conditions) { error in
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }
}

private enum TranslationError: LocalizedError {
    case notInitialized
    var errorDescription: String? { "翻訳サービスが初期化されていません" }
}
