import SwiftUI
import MPCore
import MPUI
import MPScanners
import MPHelperClient

struct TimeMachineView: View {
    @State private var scanner = TimeMachineScanner()
    @State private var helperClient = HelperClient()
    @State private var phase: ScanPhase = .idle
    @State private var result: ScanResult?
    @State private var progress: ScanProgress?
    @State private var error: String?
    @State private var showConfirmation = false
    @State private var isCleaning = false

    var body: some View {
        VStack {
            if let result = result {
                resultView(result)
            } else if phase == .scanning || phase == .analyzing || phase == .preparing {
                scanningView
            } else {
                startView
            }
        }
        .padding()
        .onAppear { helperClient.connect() }
        .onDisappear { helperClient.disconnect() }
    }

    private var startView: some View {
        VStack(spacing: 20) {
            Image(systemName: ScanCategory.timeMachine.systemImage)
                .font(.system(size: 64))
                .foregroundColor(MPColors.cleanupAccent)

            Text("Time Machine Snapshots")
                .font(MPTypography.title)

            Text("Find and remove local Time Machine snapshots that are taking up space on your startup disk.")
                .font(MPTypography.body)
                .multilineTextAlignment(.center)
                .foregroundColor(MPColors.textSecondary)
                .padding(.horizontal)

            MPButton("Scan", icon: "play.fill", style: .primary(MPColors.cleanupAccent)) {
                startScan()
            }
        }
    }

    private var scanningView: some View {
        VStack(spacing: 20) {
            IndeterminateSpinner(accentColor: MPColors.cleanupAccent)
                .frame(width: 120, height: 120)

            Text(phase.description)
                .font(MPTypography.headline)

            if let items = progress?.itemsFound {
                Text("Found \(items) snapshots")
                    .font(MPTypography.caption)
                    .foregroundColor(MPColors.textTertiary)
            }

            if let error = error {
                Text(error)
                    .font(MPTypography.caption)
                    .foregroundColor(.red)
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
                Text("Local Snapshots")
                    .font(MPTypography.title2)
                Spacer()
                Text("\(res.items.count) snapshots found")
                    .font(MPTypography.title2)
                    .foregroundColor(MPColors.cleanupAccent)
            }

            List {
                ForEach(res.items) { item in
                    ItemListRow(item: item, onToggle: { _ in })
                }
            }
            .listStyle(.inset)
            .background(MPColors.contentBackground)

            if let error = error {
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
                    isCleaning ? "Deleting…" : "Delete Snapshots",
                    icon: "trash",
                    style: .primary(MPColors.cleanupAccent)
                ) {
                    showConfirmation = true
                }
                .disabled(res.items.isEmpty || isCleaning)
            }
        }
        .confirmationDialog(
            "Delete \(res.items.count) snapshot\(res.items.count == 1 ? "" : "s")?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSnapshots(res.items)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Local snapshots will be permanently removed. This cannot be undone.")
        }
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
                    if case let .failed(msg) = update.phase {
                        self.error = msg
                    }
                }

                if let finalResult = await scanner.results() {
                    self.result = finalResult
                } else if self.error == nil {
                    self.phase = .idle
                }
            } catch {
                self.error = error.localizedDescription
                self.phase = .idle
            }
        }
    }

    private func deleteSnapshots(_ items: [ScanItem]) {
        isCleaning = true
        error = nil

        Task {
            var failures: [String] = []
            for item in items {
                do {
                    _ = try await helperClient.deleteTimeMachineSnapshot(item.name)
                } catch {
                    failures.append(item.name + ": " + error.localizedDescription)
                }
            }
            isCleaning = false
            if failures.isEmpty {
                result = nil
                phase = .idle
            } else {
                self.error = failures.joined(separator: "\n")
            }
        }
    }
}
