import SwiftUI
import MPUI

struct WelcomeStep: View {
    let onNext: () -> Void
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(MPColors.aiAccent.opacity(0.06))
                    .frame(width: 180, height: 180)
                    .scaleEffect(isAnimating ? 1.08 : 1.0)

                Circle()
                    .fill(MPColors.cleanupAccent.opacity(0.04))
                    .frame(width: 220, height: 220)
                    .scaleEffect(isAnimating ? 1.05 : 1.0)

                Image(systemName: "sparkle")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [MPColors.cleanupAccent, MPColors.aiAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .modifier(BreathingSymbolModifier())
            }

            VStack(spacing: 12) {
                Text("Welcome to MacPolish")
                    .font(MPTypography.largeTitle)
                    .foregroundStyle(MPColors.textPrimary)

                Text("Your Mac deserves to run at its best.\nLet's set things up in under a minute.")
                    .font(MPTypography.body)
                    .foregroundStyle(MPColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Spacer()

            MPButton("Get Started", icon: "arrow.right", style: .primary(MPColors.aiAccent)) {
                onNext()
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

private struct BreathingSymbolModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.symbolEffect(.breathe.byLayer, options: .repeating)
        } else {
            content.symbolEffect(.pulse, options: .repeating)
        }
    }
}
