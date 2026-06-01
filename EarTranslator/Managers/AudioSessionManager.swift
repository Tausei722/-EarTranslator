import AVFoundation

class AudioSessionManager {
    static let shared = AudioSessionManager()

    func configure() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,       // TTS 読み上げアプリ向けモード
            options: [
                .allowBluetooth,      // Bluetooth イヤホン（HFP）を有効化
                .defaultToSpeaker     // イヤホン未接続時はスピーカーから出力
            ]
        )
        try session.setActive(true)
    }
}
