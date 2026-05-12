import SwiftUI
import MPCore

public struct SidebarLabel: View {
    let category: ScanCategory
    let isActive: Bool

    public init(category: ScanCategory, isActive: Bool = false) {
        self.category = category
        self.isActive = isActive
    }

    private var accentColor: Color {
        Color.accentForGroup(category.group)
    }

    public var body: some View {
        Label {
            Text(category.rawValue)
                .font(MPTypography.sidebarItem)
                .foregroundStyle(isActive ? MPColors.textPrimary : MPColors.textSecondary)
        } icon: {
            Image(systemName: category.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(isActive ? accentColor : MPColors.textTertiary)
                .frame(width: 20)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

public struct SidebarSectionHeader: View {
    let group: ModuleGroup

    public init(group: ModuleGroup) {
        self.group = group
    }

    public var body: some View {
        Text(group.rawValue.uppercased())
            .font(MPTypography.sidebarSection)
            .foregroundStyle(MPColors.textTertiary)
            .tracking(1.2)
    }
}
