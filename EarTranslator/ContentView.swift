import SwiftUI
import Translation

struct ContentView: View {
    @StateObject private var vm = TranslatorViewModel()
    @State private var showSettings = false

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ---- Speaker B（上半分を180°回転：相手向き）----
                SpeakerPanel(
                    label: vm.selectedPair.langB.name,
                    transcript: vm.transcriptB,
                    translation: vm.translationB,
                    isRecording: vm.isRecordingB,
                    accentColor: .blue
                ) {
                    vm.startRecording(speaker: .b)
                } onRelease: {
                    vm.stopRecording(speaker: .b)
                }
                .rotationEffect(.degrees(180))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
                    .overlay(statusBar)
                    .zIndex(1)

                // ---- Speaker A（下半分：自分向き）----
                SpeakerPanel(
                    label: vm.selectedPair.langA.name,
                    transcript: vm.transcriptA,
                    translation: vm.translationA,
                    isRecording: vm.isRecordingA,
                    accentColor: .green
                ) {
                    vm.startRecording(speaker: .a)
                } onRelease: {
                    vm.stopRecording(speaker: .a)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(edges: .bottom)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationTitle("EarTranslator")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSettings) {
                SettingsView(vm: vm)
            }
            .alert("エラー", isPresented: errorBinding) {
                Button("OK") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
            .task { await vm.setup() }
            .translationTask(vm.translationConfig) { session in
                await vm.performTranslation(session: session)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if vm.isTranslating {
                ProgressView().scaleEffect(0.7)
                Text("翻訳中...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if vm.isSpeaking {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.orange)
                    .imageScale(.small)
                Text("読み上げ中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("言語ペア", selection: $vm.selectedPair) {
                    ForEach(availablePairs) { pair in
                        Text(pair.name).tag(pair)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(.regularMaterial)
    }
}

// MARK: - Speaker Panel

struct SpeakerPanel: View {
    let label: String
    let transcript: String
    let translation: String
    let isRecording: Bool
    let accentColor: Color
    let onPress: () -> Void
    let onRelease: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Text(translation.isEmpty ? " " : translation)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .foregroundStyle(accentColor)

            Text(transcript.isEmpty ? " " : transcript)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Spacer()

            ZStack {
                Circle()
                    .fill(isRecording ? accentColor : accentColor.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .scaleEffect(isRecording ? 1.15 : 1.0)
                    .animation(.spring(duration: 0.2), value: isRecording)

                Image(systemName: isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 30))
                    .foregroundStyle(isRecording ? .white : accentColor)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isRecording { onPress() } }
                    .onEnded { _ in if isRecording { onRelease() } }
            )

            Text(isRecording ? "録音中... (離すと翻訳)" : "押して話す（\(label)）")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer().frame(height: 20)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var vm: TranslatorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("使い方") {
                    Label("ボタンを押しながら話す", systemImage: "mic")
                    Label("離すと自動で翻訳・読み上げ", systemImage: "speaker.wave.2")
                    Label("上半分は相手向き（180°回転）", systemImage: "arrow.up.and.down")
                    Label("Bluetoothイヤホンは自動接続", systemImage: "airpodspro")
                }

                Section("翻訳エンジン") {
                    Label("Apple Translation（完全無料・オンデバイス）", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("初回使用時に言語モデルを自動ダウンロードします")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
