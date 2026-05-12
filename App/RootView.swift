import SwiftUI
import MPCore
import MPUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            if let category = appState.selectedCategory {
                moduleView(for: category)
            } else {
                welcomeDetail
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .background(MPColors.contentBackground)
    }

    private var sidebar: some View {
        List(selection: Binding(
            get: { appState.selectedCategory },
            set: { appState.selectedCategory = $0 }
        )) {
            ForEach(ModuleGroup.allCases) { group in
                Section {
                    ForEach(group.categories) { category in
                        SidebarLabel(
                            category: category,
                            isActive: appState.selectedCategory == category
                        )
                        .tag(category)
                    }
                } header: {
                    SidebarSectionHeader(group: group)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(MPColors.sidebarBackground)
        .safeAreaInset(edge: .top, spacing: 0) {
            sidebarHeader
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
    }

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [MPColors.cleanupAccent, MPColors.aiAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("MacPolish")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(MPColors.textPrimary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(MPColors.sidebarBackground)
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.white.opacity(0.06))

            HStack {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(MPColors.textTertiary)
                Text("Settings")
                    .font(MPTypography.caption)
                    .foregroundStyle(MPColors.textTertiary)
                Spacer()
                Text("v0.1.0")
                    .font(MPTypography.captionSmall)
                    .foregroundStyle(MPColors.textTertiary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(MPColors.sidebarBackground)
    }

    private var welcomeDetail: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(MPColors.aiAccent.opacity(0.5))
                .symbolEffect(.pulse.byLayer, options: .repeating)

            Text("Select a module to get started")
                .font(MPTypography.title2)
                .foregroundStyle(MPColors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MPColors.contentBackground)
    }

    @ViewBuilder
    private func moduleView(for category: ScanCategory) -> some View {
        switch category {
        case .systemJunk:
            SystemJunkView()
        case .trashBins:
            TrashBinsView()
        case .mailAttachments:
            MailAttachmentsView()
        case .timeMachine:
            TimeMachineView()
        default:
            ModulePlaceholderView(category: category)
        }
    }
}
