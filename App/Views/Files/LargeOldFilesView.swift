import SwiftUI
import MPCore
import MPUI
import MPScanners

struct LargeOldFilesView: View {
    @State private var scanner = LargeOldFilesScanner()
    @State private var phase: ScanPhase = .idle
    @State private var result: ScanResult?
    @State private var progress: ScanProgress?
    @State private var error: String?
    @State private var showConfirmation = false
    @State private var isCleaning = false
    @Environment(\.quarantine) private var quarantine

    var body: some View {
        VStack {
            if let result {
                resultView(result)
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
            Image(systemName: ScanCategory.largeOldFiles.systemImage)
                .font(.system(size: 64))
                .foregroundColor(MPColors.filesAccent)

            Text("Large & Old Files")
                .font(MPTypography.title)

            Text("Find files larger than 100 MB that you haven't touched in over a year.")
                .font(MPTypography.body)
                .multilineTextAlignment(.center)
                .foregroundColor(MPColors.textSecondary)
                .padding(.horizontal)

            MPButton("Scan", icon: "play.fill", style: .primary(MPColors.filesAccent)) {
                startScan()
            }
        }
    }

    private var scanningView: some View {
        VStack(spacing: 20) {
            IndeterminateSpinner(accentColor: MPColors.filesAccent)
                .frame(width: 120, height: 120)

            Text(phase.description)
                .font(MPTypography.headline)

            if let items = progress?.itemsFound, items > 0 {
                Text("Found \(items) candidates")
                    .font(MPTypography.caption)
                    .foregroundColor(MPColors.textTertiary)
            }

            MPButton("Cancel", icon: "xmark", style: .secondary) {
                Task { await scanner.cancel() }
                phase = .idle
            }
        }
    }

    private func resultView(_ res: ScanResult) -> some View {
        VStack(spacing: 20) {
            HStack {
                Text("Large & Old Files")
                    .font(MPTypography.title2)
                Spacer()
                Text(SizeFormatter.format(res.totalSize))
                    .font(MPTypography.title2)
                    .foregroundColor(MPColors.filesAccent)
            }

            if res.items.isEmpty {
                emptyResult
            } else {
                List {
                    ForEach(res.items.sorted(by: { $0.size > $1.size })) { item in
                        ItemListRow(item: item, onToggle: { _ in })
                    }
                }
                .listStyle(.inset)
                .background(MPColors.contentBackground)
            }

            if let error {
                Text(error)
                    .font(MPTypography.caption)
                    .foregroundColor(.red)
            }

            HStack {
                MPButton("Scan Again", icon: "arrow.clockwise", style: .secondary) {
                    Task { await scanner.reset() }
                    result = nil
                    phase = .idle
                    startScan()
                }
                Spacer()
                MPButton(
                    isCleaning ? "Cleaning…" : "Move to Trash",
                    icon: "trash",
                    style: .primary(MPColors.filesAccent)
                ) {
                    showConfirmation = true
                }
                .disabled(res.items.isEmpty || isCleaning)
            }
        }
        .confirmationDialog(
            "Move \(res.items.count) item\(res.items.count == 1 ? "" : "s") to the Trash?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Quarantine", role: .destructive) {
                cleanItems(res.items)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Items will be quarantined for 7 days before permanent deletion. You can restore them from Quarantine History.")
        }
    }

    private var emptyResult: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundColor(MPColors.filesAccent.opacity(0.6))
            Text("No large, old files found.")
                .font(MPTypography.headline)
            Text("Nothing in your home folder is larger than 100 MB and older than one year.")
                .font(MPTypography.caption)
                .foregroundColor(MPColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func startScan() {
        phase = .preparing
        error = nil
        result = nil

        Task {
            do {
                let stream = await scanner.scan()
                for try await update in stream {
                    self.progress = update
                    self.phase = update.phase
                }

                if let finalResult = await scanner.results() {
                    self.result = finalResult
                } else {
                    self.phase = .idle
                }
            } catch {
                self.error = error.localizedDescription
                self.phase = .idle
            }
        }
    }

    private func cleanItems(_ items: [ScanItem]) {
        isCleaning = true
        error = nil

        Task {
            do {
                let urls = items.map(\.path)
                _ = try await quarantine.quarantine(urls)
                let fm = FileManager.default
                for url in urls {
                    var trashed: NSURL?
                    try fm.trashItem(at: url, resultingItemURL: &trashed)
                }
                result = nil
                phase = .idle
            } catch {
                self.error = "Move failed: \(error.localizedDescription)"
            }
            isCleaning = false
        }
    }
}
