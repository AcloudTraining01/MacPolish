import SwiftUI
import MPCore
import MPUI
import MPScanners

struct DuplicateFinderView: View {
    @State private var scanner = DuplicateScanner()
    @State private var phase: ScanPhase = .idle
    @State private var result: ScanResult?
    @State private var progress: ScanProgress?
    @State private var error: String?
    @State private var showConfirmation = false
    @State private var isCleaning = false
    @State private var mode: DuplicateMode = .exact
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
            Image(systemName: ScanCategory.duplicateFinder.systemImage)
                .font(.system(size: 64))
                .foregroundColor(MPColors.filesAccent)

            Text("Duplicate Finder")
                .font(MPTypography.title)

            Text(modeDescription)
                .font(MPTypography.body)
                .multilineTextAlignment(.center)
                .foregroundColor(MPColors.textSecondary)
                .padding(.horizontal)

            Picker("Mode", selection: $mode) {
                Text("Exact bytes").tag(DuplicateMode.exact)
                Text("Similar images").tag(DuplicateMode.perceptual)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            MPButton("Scan", icon: "play.fill", style: .primary(MPColors.filesAccent)) {
                startScan()
            }
        }
    }

    private var modeDescription: String {
        switch mode {
        case .exact:
            return "Scans Documents, Downloads, Desktop, and Pictures for exact-byte duplicates. The oldest copy is kept; later copies become candidates for cleaning."
        case .perceptual:
            return "Scans the same scopes for visually similar images using an average-hash fingerprint. Useful for catching near-duplicate photos saved at different qualities."
        }
    }

    private var scanningView: some View {
        VStack(spacing: 20) {
            IndeterminateSpinner(accentColor: MPColors.filesAccent)
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

            if let items = progress?.itemsFound, items > 0 {
                Text("Hashed \(items) candidates")
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
        VStack(spacing: 16) {
            HStack {
                Text("Duplicates")
                    .font(MPTypography.title2)
                Text("\(res.items.count) file\(res.items.count == 1 ? "" : "s")")
                    .font(MPTypography.caption)
                    .foregroundColor(MPColors.textSecondary)
                Spacer()
                Text(SizeFormatter.format(res.totalSize))
                    .font(MPTypography.title2)
                    .foregroundColor(MPColors.filesAccent)
            }

            if res.items.isEmpty {
                emptyResult
            } else {
                groupedList(res.items)
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
                    isCleaning ? "Cleaning…" : "Move Duplicates to Trash",
                    icon: "trash",
                    style: .primary(MPColors.filesAccent)
                ) {
                    showConfirmation = true
                }
                .disabled(res.items.isEmpty || isCleaning)
            }
        }
        .confirmationDialog(
            "Move \(res.items.count) duplicate\(res.items.count == 1 ? "" : "s") to the Trash?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Quarantine", role: .destructive) {
                cleanItems(res.items)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each duplicate set keeps the oldest copy; the others are quarantined for 7 days before permanent deletion.")
        }
    }

    private func groupedList(_ items: [ScanItem]) -> some View {
        let groups = Dictionary(grouping: items, by: { $0.explanation ?? "" })
        let keys = groups.keys.sorted()
        return List {
            ForEach(keys, id: \.self) { key in
                Section {
                    ForEach(groups[key] ?? []) { item in
                        ItemListRow(item: item, onToggle: { _ in })
                    }
                } header: {
                    Text(key.isEmpty ? "Duplicate set" : key)
                        .font(MPTypography.captionSmall)
                        .foregroundColor(MPColors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .listStyle(.inset)
        .background(MPColors.contentBackground)
    }

    private var emptyResult: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundColor(MPColors.filesAccent.opacity(0.6))
            Text("No duplicates found.")
                .font(MPTypography.headline)
            Text("Documents, Downloads, Desktop, and Pictures all look unique.")
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

        let home = FileManager.default.homeDirectoryForCurrentUser
        let scopes = [
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Pictures"),
        ]
        let selectedMode = mode

        Task {
            do {
                let stream = await scanner.scan(scopes: scopes, mode: selectedMode)
                for try await update in stream {
                    self.progress = update
                    self.phase = update.phase
                }
                if let final = await scanner.results() {
                    self.result = final
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
