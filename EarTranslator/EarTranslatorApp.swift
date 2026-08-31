import SwiftUI

@main
struct EarTranslatorApp: App {
    @AppStorage("isAuthenticated") private var isAuthenticated = false

    var body: some Scene {
        WindowGroup {
            if isAuthenticated {
                ContentView()
            } else {
                PasswordGateView()
            }
        }
    }
}
