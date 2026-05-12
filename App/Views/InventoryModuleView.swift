import SwiftUI
import MPCore
import MPUI

// Generic read-only inventory view. Used by Extensions / Updater / Optimization /
// Privacy where the scan output is a flat list grouped by `explanation`. No clean
// action is wired in here on purpose — these modules are inventory-only at v1.
struct InventoryModuleView<Scanner: MPCore.Scanner>: View {
    let category: ScanCategory
    let accent: Color
    let title: String
    let subtitle: String
    let actionLabel: String
    let scanLabel: String
    let scanner: Scanner

    @State private var phase: ScanPhase = .idle
    @State private var result: ScanResult?
    @State private var progress: ScanProgress?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            if let result {
                resultView(result)
            } else if phase == .scanning || phase == .preparing {
                scanningView
            } else {
                startView
            }
        }
        .padding()
    }

    private var startView: some View {
        VStack(spacing: 20) {
            Image(systemName: category.systemImage)
                .font(.system(size: 64))
                .foregroundColor(accent)
            Text(title)
                .font(MPTypography.title)
            Text(subtitle)
                .font(MPTypography.body)
                .multilineTextAlignment(.center)
                .foregroundColor(MPColors.textSecondary)
                .padding(.horizontal)
            MPButton(scanLabel, icon: "play.fill", style: .primary(accent)) {
                runScan()
            }
        }
    }

    private var scanningView: some View {
        VStack(spacing: 20) {
            IndeterminateSpinner(accentColor: accent).frame(width: 120, height: 120)
            Text(phase.description).font(MPTypography.headline)
            if let items = progress?.itemsFound, items > 0 {
                Text("Found \(items)")
                    .font(MPTypography.caption)
                    .foregroundColor(MPColors.textTertiary)
            }
        }
    }

    private func resultView(_ res: ScanResult) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(title).font(MPTypography.title2)
                Text("\(res.items.count)")
                    .font(MPTypography.caption)
                    .foregroundColor(MPColors.textSecondary)
                Spacer()
                if res.totalSize > 0 {
                    Text(SizeFormatter.format(res.totalSize))
                        .font(MPTypography.title2)
                        .foregroundColor(accent)
                }
            }

            if res.items.isEmpty {
                emptyState
            } else {
                groupedList(res.items)
            }

            if let error {
                Text(error).font(MPTypography.caption).foregroundColor(.red)
            }

            HStack {
                Spacer()
                MPButton(scanLabel, icon: "arrow.clockwise", style: .secondary) {
                    runScan()
                }
            }
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
                    Text(key.isEmpty ? "Other" : key)
                        .font(MPTypography.captionSmall)
                        .foregroundColor(MPColors.textTertiary)
                }
            }
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundColor(accent.opacity(0.6))
            Text("Nothing to show.").font(MPTypography.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func runScan() {
        phase = .preparing
        error = nil
        result = nil
        Task {
            do {
                let stream = await scanner.scan()
                for try await update in stream {
                    self.progress = update
                    self.phase = update.phase
                    if case .failed(let msg) = update.phase {
                        self.error = msg
                    }
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
}
