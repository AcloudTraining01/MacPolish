import SwiftUI
import MPCore

public struct ItemListRow: View {
    let item: ScanItem
    let onToggle: (Bool) -> Void

    public init(item: ScanItem, onToggle: @escaping (Bool) -> Void) {
        self.item = item
        self.onToggle = onToggle
    }

    public var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { item.isSelected },
                set: { onToggle($0) }
            ))
            .toggleStyle(.checkbox)

            Image(systemName: iconForItem)
                .font(.system(size: 16))
                .foregroundStyle(colorForRisk)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(MPTypography.body)
                    .foregroundStyle(MPColors.textPrimary)
                    .lineLimit(1)

                Text(item.path.path)
                    .font(MPTypography.captionSmall)
                    .foregroundStyle(MPColors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let date = item.lastModified {
                Text(date, style: .relative)
                    .font(MPTypography.caption)
                    .foregroundStyle(MPColors.textTertiary)
            }

            Text(SizeFormatter.format(item.size))
                .font(MPTypography.monoCaption)
                .foregroundStyle(MPColors.textSecondary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(MPColors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(MPColors.cardBorder, lineWidth: 0.5)
                )
        )
    }

    private var iconForItem: String {
        switch item.riskLevel {
        case .safe: return "checkmark.circle"
        case .cautionary: return "exclamationmark.triangle"
        case .dangerous: return "xmark.octagon"
        }
    }

    private var colorForRisk: Color {
        switch item.riskLevel {
        case .safe: return MPColors.success
        case .cautionary: return MPColors.warning
        case .dangerous: return MPColors.danger
        }
    }
}
