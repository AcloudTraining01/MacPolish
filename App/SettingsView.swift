import SwiftUI
import MPCore
import MPUI
import MPAI

struct SettingsView: View {
    @State private var selectedModel = "anthropic/claude-opus-4.7"
    @State private var apiKey = ""
    @State private var showKey = false

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            aiTab
                .tabItem {
                    Label("AI Assistant", systemImage: "brain.head.profile")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 360)
    }

    private var generalTab: some View {
        Form {
            Section("Appearance") {
                Text("Theme settings will appear here")
                    .foregroundStyle(.secondary)
            }

            Section("Quarantine") {
                Text("Quarantined files are kept for 7 days before permanent deletion.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var aiTab: some View {
        Form {
            Section("OpenRouter API Key") {
                HStack {
                    if showKey {
                        TextField("sk-or-...", text: $apiKey)
                    } else {
                        SecureField("sk-or-...", text: $apiKey)
                    }
                    Button(showKey ? "Hide" : "Show") {
                        showKey.toggle()
                    }
                }

                Link("Get an OpenRouter API key",
                     destination: URL(string: "https://openrouter.ai/keys")!)
                    .font(.caption)
            }

            Section("Model") {
                Picker("Model", selection: $selectedModel) {
                    ForEach(MPAI.OpenRouterModel.curated) { model in
                        Text("\(model.name) (\(model.provider))")
                            .tag(model.id)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "sparkle")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        colors: [MPColors.cleanupAccent, MPColors.aiAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("MacPolish")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Text("Version 0.1.0 (Skeleton)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("A powerful Mac cleaner with AI-driven insights.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
