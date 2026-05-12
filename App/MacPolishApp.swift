import SwiftUI
import MPCore
import MPUI
import MPScanners
import MPAI
import MPHelperClient

@main
struct MacPolishApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            if appState.hasCompletedOnboarding {
                RootView()
                    .environment(appState)
                    .environment(\.quarantine, Quarantine())
            } else {
                OnboardingView(onComplete: {
                    appState.hasCompletedOnboarding = true
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                })
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 720)

        Settings {
            SettingsView()
        }
    }
}

@Observable
@MainActor
final class AppState {
    var hasCompletedOnboarding: Bool
    var selectedCategory: ScanCategory? = .smartScan
    var profileType: ProfileType?

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if let saved = UserDefaults.standard.string(forKey: "profileType") {
            self.profileType = ProfileType(rawValue: saved)
        }
    }
}
