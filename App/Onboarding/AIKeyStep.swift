import SwiftUI
import MPUI

struct AIKeyStep: View {
    @Binding var apiKey: String
    let onNext: () -> Void
    let onSkip: () -> Void
    @State private var showKey = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(MPColors.aiAccent.opacity(0.7))
                .symbolEffect(.pulse.byLayer, options: .repeating)

            VStack(spacing: 12) {
                Text("AI Assistant")
                    .font(MPTypography.title)
                    .foregroundStyle(MPColors.textPrimary)

                Text("Connect your OpenRouter API key to unlock\nAI-powered cleanup recommendations and file insights.")
                    .font(MPTypography.body)
                    .foregroundStyle(MPColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            VStack(spacing: 12) {
                HStack {
                    if showKey {
                        TextField("sk-or-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-or-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button(action: { showKey.toggle() }) {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundStyle(MPColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: 360)

                Link(destination: URL(string: "https://openrouter.ai/keys")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Get an OpenRouter API key")
                    }
                    .font(MPTypography.caption)
                    .foregroundStyle(MPColors.aiAccent)
                }

                Text("You pay OpenRouter directly. MacPolish never sees your billing.")
                    .font(MPTypography.captionSmall)
                    .foregroundStyle(MPColors.textTertiary)
            }

            HStack(spacing: 16) {
                MPButton("Save & Continue", icon: "checkmark", style: .primary(MPColors.aiAccent)) {
                    onNext()
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(apiKey.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
            }

            Spacer()

            Button("Skip for now") {
                onSkip()
            }
            .buttonStyle(.plain)
            .font(MPTypography.caption)
            .foregroundStyle(MPColors.textTertiary)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
