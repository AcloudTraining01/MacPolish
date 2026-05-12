import SwiftUI
import MPCore
import MPUI
import MPScanners

struct BatteryHealthView: View {
    @State private var reader = BatteryReader()
    @State private var snapshot: BatterySnapshot?
    @State private var phase: ScanPhase = .idle
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            if let snapshot {
                snapshotView(snapshot)
            } else if phase == .scanning || phase == .preparing {
                ProgressView()
            } else if let error {
                noBatteryView(message: error)
            } else {
                startView
            }
        }
        .padding()
        .onAppear { runRead() }
    }

    private var startView: some View {
        VStack(spacing: 16) {
            Image(systemName: ScanCategory.batteryHealth.systemImage)
                .font(.system(size: 64))
                .foregroundColor(MPColors.speedAccent)
            Text("Battery Health")
                .font(MPTypography.title)
            MPButton("Read Battery", icon: "play.fill", style: .primary(MPColors.speedAccent)) {
                runRead()
            }
        }
    }

    private func noBatteryView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 56))
                .foregroundColor(MPColors.textTertiary)
            Text(message)
                .font(MPTypography.headline)
                .foregroundColor(MPColors.textSecondary)
        }
    }

    private func snapshotView(_ snap: BatterySnapshot) -> some View {
        VStack(spacing: 20) {
            HStack {
                Text("Battery Health")
                    .font(MPTypography.title2)
                Spacer()
                Text("\(Int(snap.healthPercent))%")
                    .font(MPTypography.title)
                    .foregroundColor(healthColor(snap.healthPercent))
            }

            metricsGrid(snap)

            if snap.healthPercent < 80 {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(MPColors.warning)
                    Text("Apple considers a Mac battery worn out at 80% maximum capacity. A service appointment may restore capacity.")
                        .font(MPTypography.caption)
                        .foregroundColor(MPColors.textSecondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 6).fill(MPColors.warning.opacity(0.08)))
            }

            HStack {
                Spacer()
                MPButton("Refresh", icon: "arrow.clockwise", style: .secondary) {
                    runRead()
                }
            }
        }
    }

    private func metricsGrid(_ snap: BatterySnapshot) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            metric(label: "Cycle count", value: "\(snap.cycleCount)")
            metric(label: "State", value: snap.isCharging ? "Charging" : (snap.isPluggedIn ? "Plugged in" : "On battery"))
            metric(label: "Charge", value: "\(Int(snap.stateOfChargePercent))%")
            metric(label: "Temperature", value: String(format: "%.1f°C", snap.temperatureCelsius))
            metric(label: "Design capacity", value: "\(snap.designCapacityMAh) mAh")
            metric(label: "Max capacity", value: "\(snap.maxCapacityMAh) mAh")
        }
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(MPTypography.captionSmall).foregroundColor(MPColors.textTertiary)
            Text(value).font(MPTypography.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(MPColors.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MPColors.cardBorder, lineWidth: 0.5))
        )
    }

    private func healthColor(_ percent: Double) -> Color {
        if percent < 80 { return MPColors.warning }
        if percent < 50 { return MPColors.danger }
        return MPColors.success
    }

    private func runRead() {
        phase = .preparing
        error = nil
        Task {
            let stream = await reader.scan()
            for try await update in stream {
                phase = update.phase
                if case .failed(let msg) = update.phase {
                    error = msg
                }
            }
            snapshot = await reader.currentSnapshot()
        }
    }
}
