import AVFoundation

class AudioSessionManager {
    static let shared = AudioSessionManager()

    /// Bluetoothイヤホン（HFP/A2DP）でマイク入力と音声出力を同時に使う設定
    func configure() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,  // AEC有効・BT HFPは自動有効
            options: []        // .defaultToSpeaker を外す→イヤホン接続時はイヤホンから出力
        )
        try session.setActive(true)
    }
}
