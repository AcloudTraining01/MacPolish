import SwiftUI
import MPCore
import MPUI
import MPHelperClient

struct MaintenanceView: View {
    @State private var helper = HelperClient()
    @State private var runningAction: String?
    @State private var log: [String] = []

    private struct Action: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let perform: (HelperClient) async throws -> Bool
    }

    private let actions: [Action] = [
        .init(
            id: "periodic_daily",
            title: "Run Daily Maintenance",
            subtitle: "/usr/sbin/periodic daily — log rotation, temp cleanup",
            icon: "sunrise"
        ) { try await $0.runMaintenanceScript("periodic_daily") },
        .init(
            id: "periodic_weekly",
            title: "Run Weekly Maintenance",
            subtitle: "/usr/sbin/periodic weekly — locate / whatis databases",
            icon: "calendar"
        ) { try await $0.runMaintenanceScript("periodic_weekly") },
        .init(
            id: "periodic_monthly",
            title: "Run Monthly Maintenance",
            subtitle: "/usr/sbin/periodic monthly — login accounting rotation",
            icon: "calendar.badge.clock"
        ) { try await $0.runMaintenanceScript("periodic_monthly") },
        .init(
            id: "purge",
            title: "Purge Inactive Memory",
            subtitle: "/usr/sbin/purge — frees inactive RAM pages",
            icon: "memorychip"
        ) { try await $0.runMaintenanceScript("purge") },
        .init(
            id: "dscacheutil_flush",
            title: "Flush DNS Cache",
            subtitle: "dscacheutil -flushcache + killall -HUP mDNSResponder",
            icon: "network"
        ) { try await $0.flushDNSCache() },
        .init(
            id: "mdutil_erase",
            title: "Reindex Spotlight (boot volume)",
            subtitle: "mdutil -E / — rebuilds the search index from scratch",
            icon: "magnifyingglass"
        ) { try await $0.reindexSpotlight(volume: "/") },
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            actionsList
            logPane
        }
        .padding()
        .onAppear { helper.connect() }
        .onDisappear { helper.disconnect() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: ScanCategory.maintenance.systemImage)
                .font(.system(size: 24))
                .foregroundColor(MPColors.speedAccent)
            Text("Maintenance")
                .font(MPTypography.title2)
            Spacer()
            Text("All actions run through the privileged helper")
                .font(MPTypography.captionSmall)
                .foregroundColor(MPColors.textTertiary)
        }
    }

    private var actionsList: some View {
        VStack(spacing: 8) {
            ForEach(actions) { action in
                actionRow(action)
            }
        }
    }

    private func actionRow(_ action: Action) -> some View {
        HStack(spacing: 12) {
            Image(systemName: action.icon)
                .frame(width: 28)
                .foregroundColor(MPColors.speedAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title).font(MPTypography.body)
                Text(action.subtitle)
                    .font(MPTypography.captionSmall)
                    .foregroundColor(MPColors.textTertiary)
            }
            Spacer()
            MPButton(
                runningAction == action.id ? "Running…" : "Run",
                icon: "play.fill",
                style: .secondary
            ) {
                run(action)
            }
            .disabled(runningAction != nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(MPColors.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(MPColors.cardBorder, lineWidth: 0.5))
        )
    }

    private var logPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Activity")
                .font(MPTypography.captionSmall)
                .foregroundColor(MPColors.textTertiary)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(MPTypography.monoCaption)
                            .foregroundColor(MPColors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(MPColors.contentBackground)
            )
        }
    }

    private func run(_ action: Action) {
        runningAction = action.id
        let timestamp = Self.timestamp()
        log.insert("[\(timestamp)] \(action.title) — starting", at: 0)
        Task {
            do {
                _ = try await action.perform(helper)
                log.insert("[\(Self.timestamp())] \(action.title) — done", at: 0)
            } catch {
                log.insert("[\(Self.timestamp())] \(action.title) — \(error.localizedDescription)", at: 0)
            }
            runningAction = nil
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
