import AVFoundation

class AudioSessionManager {
    static let shared = AudioSessionManager()

    /// Bluetoothイヤホン（HFP/A2DP）でマイク入力と音声出力を同時に使う設定
    func configure() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [
                .allowBluetoothHFP,    // HFP（マイク付きBT、AirPods等）
                .allowBluetoothA2DP,   // A2DP（高音質出力）
                .defaultToSpeaker      // BT未接続時はスピーカー出力
            ]
        )
        try session.setActive(true)
    }
}
