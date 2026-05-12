import SwiftUI
import MPCore
import MPUI
import MPScanners

struct SystemMonitorView: View {
    @State private var collector = SystemMonitorCollector()
    @State private var snapshot: SystemSnapshot?
    @State private var streamTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            header
            if let snapshot {
                cards(snapshot)
            } else {
                ProgressView("Sampling…").padding()
            }
            footnote
        }
        .padding()
        .onAppear { startStream() }
        .onDisappear { streamTask?.cancel(); streamTask = nil }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: ScanCategory.systemMonitor.systemImage)
                .font(.system(size: 24))
                .foregroundColor(MPColors.speedAccent)
            Text("System Monitor")
                .font(MPTypography.title2)
            Spacer()
            if let snap = snapshot {
                Text(snap.timestamp, style: .time)
                    .font(MPTypography.captionSmall)
                    .foregroundColor(MPColors.textTertiary)
            }
        }
    }

    private func cards(_ snap: SystemSnapshot) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            card(
                title: "CPU",
                primary: "\(Int(snap.cpuBusyPercent))%",
                detail: "user \(Int(snap.cpuUserPercent))% · system \(Int(snap.cpuSystemPercent))% · idle \(Int(snap.cpuIdlePercent))%",
                tint: snap.cpuBusyPercent > 80 ? MPColors.warning : MPColors.speedAccent
            )
            card(
                title: "Memory",
                primary: "\(Int(snap.memoryPressurePercent))%",
                detail: "\(SizeFormatter.format(Int64(snap.memoryUsedBytes))) of \(SizeFormatter.format(Int64(snap.memoryTotalBytes)))",
                tint: snap.memoryPressurePercent > 85 ? MPColors.warning : MPColors.speedAccent
            )
        }
    }

    private func card(title: String, primary: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(MPTypography.captionSmall)
                .foregroundColor(MPColors.textTertiary)
            Text(primary)
                .font(MPTypography.title)
                .foregroundColor(tint)
            Text(detail)
                .font(MPTypography.captionSmall)
                .foregroundColor(MPColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(MPColors.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MPColors.cardBorder, lineWidth: 0.5))
        )
    }

    private var footnote: some View {
        Text("Polling at 1 Hz. CPU figures are derived from kernel tick deltas; memory usage is active + inactive + wired + compressed pages over hw.memsize.")
            .font(MPTypography.captionSmall)
            .foregroundColor(MPColors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func startStream() {
        streamTask?.cancel()
        streamTask = Task {
            let stream = await collector.snapshotStream(intervalSeconds: 1.0)
            for await snap in stream {
                if Task.isCancelled { break }
                snapshot = snap
            }
        }
    }
}
