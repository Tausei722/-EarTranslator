import SwiftUI

private let correctPassword = "1128"

struct PasswordGateView: View {
    @AppStorage("isAuthenticated") private var isAuthenticated = false
    @State private var input = ""
    @State private var shake = false
    @State private var showError = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.primary)
                Text("リオ小池 英語翻訳")
                    .font(.title2.weight(.semibold))
                Text("パスワードを入力してください")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                SecureField("パスワード", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .frame(maxWidth: 280)
                    .focused($focused)
                    .onSubmit { attempt() }
                    .offset(x: shake ? -8 : 0)
                    .animation(shake ? .default.repeatCount(4, autoreverses: true).speed(6) : .default, value: shake)

                if showError {
                    Text("パスワードが違います")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button(action: attempt) {
                    Text("ロック解除")
                        .frame(width: 280)
                }
                .buttonStyle(.borderedProminent)
                .disabled(input.isEmpty)
            }

            Spacer()
        }
        .onAppear { focused = true }
    }

    private func attempt() {
        if input == correctPassword {
            isAuthenticated = true
        } else {
            input = ""
            showError = true
            shake = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { shake = false }
        }
    }
}
