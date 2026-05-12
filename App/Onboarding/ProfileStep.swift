import SwiftUI
import MPCore
import MPUI

struct ProfileStep: View {
    @Binding var selectedProfile: ProfileType?
    let onComplete: () -> Void
    @State private var hoveredProfile: ProfileType?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 12) {
                Text("How do you use this Mac?")
                    .font(MPTypography.title)
                    .foregroundStyle(MPColors.textPrimary)

                Text("This helps MacPolish prioritize the right cleanup modules for you.")
                    .font(MPTypography.body)
                    .foregroundStyle(MPColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ], spacing: 12) {
                ForEach(ProfileType.allCases) { profile in
                    profileCard(profile)
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            MPButton("Start Using MacPolish", icon: "sparkles", style: .primary(MPColors.cleanupAccent)) {
                onComplete()
            }
            .disabled(selectedProfile == nil)
            .opacity(selectedProfile == nil ? 0.5 : 1.0)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func profileCard(_ profile: ProfileType) -> some View {
        let isSelected = selectedProfile == profile
        let isHovered = hoveredProfile == profile

        return Button(action: { selectedProfile = profile }) {
            VStack(spacing: 12) {
                Image(systemName: profile.systemImage)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(isSelected ? MPColors.aiAccent : MPColors.textSecondary)

                Text(profile.rawValue)
                    .font(MPTypography.headline)
                    .foregroundStyle(isSelected ? MPColors.textPrimary : MPColors.textSecondary)

                Text(profile.description)
                    .font(MPTypography.captionSmall)
                    .foregroundStyle(MPColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected
                          ? MPColors.aiAccent.opacity(0.1)
                          : isHovered
                              ? MPColors.elevatedBackground
                              : MPColors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isSelected
                                    ? MPColors.aiAccent.opacity(0.5)
                                    : MPColors.cardBorder,
                                lineWidth: isSelected ? 1.5 : 0.5
                            )
                    )
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredProfile = hovering ? profile : nil
        }
    }
}
