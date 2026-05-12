import SwiftUI
import MPCore

public struct ModulePlaceholderView: View {
    let category: ScanCategory
    @State private var isAnimating = false

    public init(category: ScanCategory) {
        self.category = category
    }

    private var accentColor: Color {
        Color.accentForGroup(category.group)
    }

    public var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.08))
                    .frame(width: 140, height: 140)
                    .scaleEffect(isAnimating ? 1.05 : 1.0)

                Circle()
                    .fill(accentColor.opacity(0.04))
                    .frame(width: 180, height: 180)
                    .scaleEffect(isAnimating ? 1.08 : 1.0)

                Image(systemName: category.systemImage)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(accentColor.opacity(0.6))
                    .symbolEffect(.pulse.byLayer, options: .repeating)
            }

            VStack(spacing: 12) {
                Text(category.rawValue)
                    .font(MPTypography.title)
                    .foregroundStyle(MPColors.textPrimary)

                Text("This module is coming soon")
                    .font(MPTypography.body)
                    .foregroundStyle(MPColors.textTertiary)
            }

            Button(action: {}) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("Scan")
                        .font(MPTypography.headline)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(accentColor.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(accentColor.opacity(0.4), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(true)
            .opacity(0.5)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MPColors.contentBackground)
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}
