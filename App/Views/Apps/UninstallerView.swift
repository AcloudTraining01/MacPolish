import SwiftUI
import MPCore
import MPUI
import MPScanners

struct UninstallerView: View {
    @State private var scanner = UninstallerScanner()
    @State private var phase: ScanPhase = .idle
    @State private var uninstallables: [Uninstallable] = []
    @State private var selectedIDs: Set<UUID> = []
    @State private var progress: ScanProgress?
    @State private var error: String?
    @State private var showConfirmation = false
    @State private var isUninstalling = false
    @State private var expandedID: UUID?
    @Environment(\.quarantine) private var quarantine

    var body: some View {
        VStack {
            if !uninstallables.isEmpty {
                resultView
            } else if phase == .scanning || phase == .analyzing || phase == .preparing {
                scanningView
            } else {
                startView
            }
        }
        .padding()
    }

    private var startView: some View {
        VStack(spacing: 20) {
            Image(systemName: ScanCategory.uninstaller.systemImage)
                .font(.system(size: 64))
                .foregroundColor(MPColors.appsAccent)

            Text("Uninstaller")
                .font(MPTypography.title)

            Text("Find apps in /Applications and ~/Applications along with their leftover support files, caches, and preferences.")
                .font(MPTypography.body)
                .multilineTextAlignment(.center)
                .foregroundColor(MPColors.textSecondary)
                .padding(.horizontal)

            MPButton("Scan Applications", icon: "play.fill", style: .primary(MPColors.appsAccent)) {
                startScan()
            }
        }
    }

    private var scanningView: some View {
        VStack(spacing: 20) {
            IndeterminateSpinner(accentColor: MPColors.appsAccent)
                .frame(width: 120, height: 120)
            Text(phase.description)
                .font(MPTypography.headline)
            if let currentPath = progress?.currentPath {
                Text(currentPath)
                    .font(MPTypography.caption)
                    .foregroundColor(MPColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 420)
            }
            MPButton("Cancel", icon: "xmark", style: .secondary) {
                Task { await scanner.cancel() }
                phase = .idle
            }
        }
    }

    private var resultView: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Uninstaller")
                    .font(MPTypography.title2)
                Text("\(uninstallables.count) app\(uninstallables.count == 1 ? "" : "s")")
                    .font(MPTypography.caption)
                    .foregroundColor(MPColors.textSecondary)
                Spacer()
                Text(SizeFormatter.format(totalSelectedSize))
                    .font(MPTypography.title2)
                    .foregroundColor(MPColors.appsAccent)
            }

            List {
                ForEach(uninstallables) { unit in
                    appRow(unit)
                }
            }
            .listStyle(.inset)

            if let error {
                Text(error)
                    .font(MPTypography.caption)
                    .foregroundColor(.red)
            }

            HStack {
                MPButton("Scan Again", icon: "arrow.clockwise", style: .secondary) {
                    Task { await scanner.reset() }
                    uninstallables = []
                    selectedIDs = []
                    phase = .idle
                    startScan()
                }
                Spacer()
                MPButton(
                    isUninstalling
                        ? "Uninstalling…"
                        : "Uninstall \(selectedIDs.count) Selected",
                    icon: "trash",
                    style: .primary(MPColors.appsAccent)
                ) {
                    showConfirmation = true
                }
                .disabled(selectedIDs.isEmpty || isUninstalling)
            }
        }
        .confirmationDialog(
            "Uninstall \(selectedIDs.count) app\(selectedIDs.count == 1 ? "" : "s")?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Quarantine", role: .destructive) {
                uninstallSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app bundle and all matching leftover paths will be quarantined for 7 days. Restore from Quarantine History to roll back.")
        }
    }

    private func appRow(_ unit: Uninstallable) -> some View {
        let isSelected = selectedIDs.contains(unit.id)
        let isExpanded = expandedID == unit.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { isSelected },
                    set: { newValue in
                        if newValue { selectedIDs.insert(unit.id) }
                        else { selectedIDs.remove(unit.id) }
                    }
                ))
                .toggleStyle(.checkbox)

                Image(systemName: "app.fill")
                    .foregroundColor(MPColors.appsAccent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(unit.displayName)
                        .font(MPTypography.body)
                    Text(unit.bundleID)
                        .font(MPTypography.captionSmall)
                        .foregroundColor(MPColors.textTertiary)
                }

                Spacer()

                Text("\(unit.leftovers.count) leftover\(unit.leftovers.count == 1 ? "" : "s")")
                    .font(MPTypography.caption)
                    .foregroundColor(MPColors.textTertiary)

                Text(SizeFormatter.format(unit.totalSize))
                    .font(MPTypography.monoCaption)
                    .foregroundColor(MPColors.textSecondary)
                    .frame(width: 70, alignment: .trailing)

                Button {
                    expandedID = isExpanded ? nil : unit.id
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(MPColors.textTertiary)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    leftoverRow(label: "App bundle", value: unit.appURL.path, size: unit.appSize)
                    ForEach(unit.leftovers, id: \.url) { leftover in
                        leftoverRow(
                            label: leftover.kind,
                            value: leftover.url.path,
                            size: leftover.size
                        )
                    }
                    if unit.leftovers.isEmpty {
                        Text("No leftover paths detected.")
                            .font(MPTypography.captionSmall)
                            .foregroundColor(MPColors.textTertiary)
                    }
                }
                .padding(.leading, 44)
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 4)
    }

    private func leftoverRow(label: String, value: String, size: Int64) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(MPTypography.captionSmall)
                .foregroundColor(MPColors.textSecondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(MPTypography.captionSmall)
                .foregroundColor(MPColors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(SizeFormatter.format(size))
                .font(MPTypography.monoCaption)
                .foregroundColor(MPColors.textTertiary)
        }
    }

    private var totalSelectedSize: Int64 {
        uninstallables.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.totalSize }
    }

    private func startScan() {
        phase = .preparing
        error = nil
        uninstallables = []
        selectedIDs = []

        Task {
            do {
                let stream = await scanner.scan()
                for try await update in stream {
                    self.progress = update
                    self.phase = update.phase
                }
                self.uninstallables = await scanner.uninstallableList()
                if uninstallables.isEmpty {
                    phase = .idle
                }
            } catch {
                self.error = error.localizedDescription
                self.phase = .idle
            }
        }
    }

    private func uninstallSelected() {
        isUninstalling = true
        error = nil

        Task {
            do {
                for unit in uninstallables where selectedIDs.contains(unit.id) {
                    let paths = [unit.appURL] + unit.leftovers.map(\.url)
                    _ = try await quarantine.quarantine(paths)
                }
                let remaining = await scanner.uninstallableList()
                uninstallables = remaining.filter { !selectedIDs.contains($0.id) }
                selectedIDs = []
                if uninstallables.isEmpty { phase = .idle }
            } catch {
                self.error = "Uninstall failed: \(error.localizedDescription)"
            }
            isUninstalling = false
        }
    }
}
