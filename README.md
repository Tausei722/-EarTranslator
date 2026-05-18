# EarTranslator

Bluetoothイヤホン対応のリアルタイム同時翻訳iOSアプリ（**完全無料・APIキー不要**）

## 技術構成

| 機能 | 技術 | コスト |
|------|------|--------|
| 音声認識（STT） | SFSpeechRecognizer (Apple) | 無料 |
| 翻訳 | Google ML Kit Translate（オンデバイス） | 無料 |
| 読み上げ（TTS） | AVSpeechSynthesizer (Apple) | 無料 |
| BT出力 | AVAudioSession (.allowBluetooth) | 無料 |

## セットアップ手順

### 1. Xcodeでプロジェクト作成
- Xcode → New Project → App
- Product Name: `EarTranslator`
- Interface: SwiftUI / Language: Swift

### 2. ML Kit パッケージを追加（SPM）
- File → Add Package Dependencies
- URL: `https://github.com/google/GoogleMLKit-iOS`
- バージョン: 最新 (Up to Next Major)
- 追加するProduct: **MLKitTranslate** にチェック

### 3. ファイルを追加
- `EarTranslator/` フォルダ内の `.swift` ファイルをすべてドラッグ＆ドロップ

### 4. Info.plist に権限を追加
- `NSMicrophoneUsageDescription` → "翻訳のためにマイクを使用します"
- `NSSpeechRecognitionUsageDescription` → "音声をテキストに変換して翻訳します"

### 5. iPhone実機でビルド・実行
- シミュレーターでは音声認識が動きません

## 使い方

```
[自分（日本語）]  下半分のマイクボタンを長押しして日本語で話す
                 ↓ 離すと翻訳（初回はMLモデルDL約15MB）
                 英語で読み上げ → 相手のイヤホンへ

[相手（英語）]   上半分のマイクボタンを長押しして英語で話す（画面が180°反転）
                 ↓ 離すと翻訳
                 日本語で読み上げ → 自分のイヤホンへ
```
# -EarTranslator
