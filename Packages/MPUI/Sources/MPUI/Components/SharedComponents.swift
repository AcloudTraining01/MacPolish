import SwiftUI
import MPCore

public struct MPCard<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(MPColors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(MPColors.cardBorder, lineWidth: 0.5)
                    )
            )
    }
}

public struct MPButton: View {
    let title: String
    let icon: String?
    let style: ButtonVariant
    let action: () -> Void

    public enum ButtonVariant {
        case primary(Color)
        case secondary
        case destructive
    }

    public init(
        _ title: String,
        icon: String? = nil,
        style: ButtonVariant = .primary(MPColors.cleanupAccent),
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(MPTypography.headline)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch style {
        case .primary(let color): return color.opacity(0.2)
        case .secondary: return MPColors.elevatedBackground
        case .destructive: return MPColors.danger.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary(let color): return color
        case .secondary: return MPColors.textSecondary
        case .destructive: return MPColors.danger
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary(let color): return color.opacity(0.3)
        case .secondary: return MPColors.cardBorder
        case .destructive: return MPColors.danger.opacity(0.3)
        }
    }
}
