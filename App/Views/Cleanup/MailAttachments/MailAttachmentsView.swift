import SwiftUI
import MPCore
import MPUI
import MPScanners

struct MailAttachmentsView: View {
    @State private var scanner = MailAttachmentsScanner()
    @State private var phase: ScanPhase = .idle
    @State private var result: ScanResult?
    @State private var progress: ScanProgress?
    @State private var error: String?
    @State private var showConfirmation = false
    @State private var isCleaning = false
    @Environment(\.quarantine) private var quarantine

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
    }

    private var startView: some View {
        VStack(spacing: 20) {
            Image(systemName: ScanCategory.mailAttachments.systemImage)
                .font(.system(size: 64))
                .foregroundColor(MPColors.cleanupAccent)

            Text("Mail Attachments")
                .font(MPTypography.title)

            Text("Find and safely remove large email attachments saved locally by the Mail app.")
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

            if let items = progress?.itemsFound, let bytes = progress?.bytesFound {
                Text("Found \(items) items (\(SizeFormatter.format(bytes)))")
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
                Text("Mail Attachments")
                    .font(MPTypography.title2)
                Spacer()
                Text(SizeFormatter.format(res.totalSize))
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
                    isCleaning ? "Cleaning…" : "Clean",
                    icon: "trash",
                    style: .primary(MPColors.cleanupAccent)
                ) {
                    showConfirmation = true
                }
                .disabled(res.items.isEmpty || isCleaning)
            }
        }
        .confirmationDialog(
            "Remove \(res.items.count) attachment\(res.items.count == 1 ? "" : "s")?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Attachments", role: .destructive) {
                cleanAttachments(res.items)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Attachments will be quarantined for 7 days before permanent deletion. You can restore them from Quarantine History.")
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

    private func cleanAttachments(_ items: [ScanItem]) {
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
                self.error = "Clean failed: \(error.localizedDescription)"
            }
            isCleaning = false
        }
    }
}
