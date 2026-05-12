import SwiftUI
import MPCore
import MPUI

struct OnboardingView: View {
    @State private var currentStep = 0
    @State private var selectedProfile: ProfileType?
    @State private var apiKey = ""
    let onComplete: () -> Void

    private let totalSteps = 5

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 0) {
                progressBar

                Group {
                    switch currentStep {
                    case 0: WelcomeStep(onNext: advance)
                    case 1: FDAStep(onNext: advance, onSkip: advance)
                    case 2: HelperStep(onNext: advance, onSkip: advance)
                    case 3:
                        if DevAPIKey.bundled != nil {
                            Color.clear.onAppear(perform: advance)
                        } else {
                            AIKeyStep(apiKey: $apiKey, onNext: advance, onSkip: advance)
                        }
                    case 4: ProfileStep(selectedProfile: $selectedProfile, onComplete: completeOnboarding)
                    default: EmptyView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    private var backgroundGradient: some View {
        ZStack {
            MPColors.contentBackground

            RadialGradient(
                colors: [
                    MPColors.aiAccent.opacity(0.06),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 100,
                endRadius: 500
            )

            RadialGradient(
                colors: [
                    MPColors.cleanupAccent.opacity(0.04),
                    Color.clear
                ],
                center: .bottomLeading,
                startRadius: 50,
                endRadius: 400
            )
        }
        .ignoresSafeArea()
    }

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep
                          ? MPColors.aiAccent
                          : MPColors.textTertiary.opacity(0.3))
                    .frame(height: 3)
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.4)) {
            currentStep += 1
        }
    }

    private func completeOnboarding() {
        if let profile = selectedProfile {
            UserDefaults.standard.set(profile.rawValue, forKey: "profileType")
        }
        onComplete()
    }
}
