import SwiftUI
import AppKit
import MPCore
import MPUI
import MPScanners

struct ShredderView: View {
    @State private var engine = ShredderEngine()
    @State private var queue: [URL] = []
    @State private var isShredding = false
    @State private var showConfirmation = false
    @State private var lastOutcomes: [ShredderEngine.ShredOutcome] = []
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            header
            if queue.isEmpty {
                emptyState
            } else {
                queueList
            }
            disclaimer
            footer
        }
        .padding()
        .onAppear {
            Task { queue = await engine.queuedURLs() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: ScanCategory.shredder.systemImage)
                .font(.system(size: 24))
                .foregroundColor(MPColors.filesAccent)
            Text("Shredder")
                .font(MPTypography.title2)
            Spacer()
            MPButton("Add Files…", icon: "plus", style: .secondary) {
                pickFiles()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 44))
                .foregroundColor(MPColors.textTertiary)
            Text("No files queued.")
                .font(MPTypography.headline)
            Text("Pick files to overwrite in place and unlink. Once shredded, files cannot be recovered through the Trash.")
                .font(MPTypography.caption)
                .foregroundColor(MPColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var queueList: some View {
        List {
            ForEach(queue, id: \.self) { url in
                HStack(spacing: 12) {
                    Image(systemName: "doc")
                        .foregroundColor(MPColors.warning)
                    VStack(alignment: .leading) {
                        Text(url.lastPathComponent)
                            .font(MPTypography.body)
                        Text(url.path)
                            .font(MPTypography.captionSmall)
                            .foregroundColor(MPColors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text(sizeDescription(for: url))
                        .font(MPTypography.monoCaption)
                        .foregroundColor(MPColors.textSecondary)
                    Button {
                        Task {
                            await engine.dequeue(url)
                            queue = await engine.queuedURLs()
                        }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundColor(MPColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.inset)
        .frame(maxHeight: .infinity)
    }

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(MPColors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Shredding is permanent and bypasses the Trash.")
                    .font(MPTypography.caption)
                    .foregroundColor(MPColors.textPrimary)
                Text("On APFS SSDs, multi-pass overwrite is largely theatrical — the file system writes to free blocks instead of in place. For sensitive data on SSDs, full-disk encryption is what actually protects you.")
                    .font(MPTypography.captionSmall)
                    .foregroundColor(MPColors.textSecondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(MPColors.warning.opacity(0.08))
        )
    }

    private var footer: some View {
        HStack {
            if !lastOutcomes.isEmpty {
                let failed = lastOutcomes.filter { !$0.success }
                Text(failed.isEmpty
                    ? "Shredded \(lastOutcomes.count) file\(lastOutcomes.count == 1 ? "" : "s")."
                    : "\(lastOutcomes.count - failed.count) shredded, \(failed.count) failed.")
                    .font(MPTypography.caption)
                    .foregroundColor(failed.isEmpty ? MPColors.success : MPColors.warning)
            }
            if let error {
                Text(error)
                    .font(MPTypography.caption)
                    .foregroundColor(.red)
            }
            Spacer()
            MPButton(
                isShredding ? "Shredding…" : "Shred",
                icon: "scissors",
                style: .primary(MPColors.danger)
            ) {
                showConfirmation = true
            }
            .disabled(queue.isEmpty || isShredding)
        }
        .confirmationDialog(
            "Shred \(queue.count) file\(queue.count == 1 ? "" : "s")?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Shred Permanently", role: .destructive) {
                runShred()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This overwrites each file three times (zeros, ones, random) then unlinks it. This cannot be undone.")
        }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            let urls = panel.urls
            Task {
                await engine.enqueue(urls)
                queue = await engine.queuedURLs()
            }
        }
    }

    private func runShred() {
        isShredding = true
        error = nil
        lastOutcomes = []
        Task {
            let outcomes = await engine.shred()
            lastOutcomes = outcomes
            queue = await engine.queuedURLs()
            isShredding = false
        }
    }

    private func sizeDescription(for url: URL) -> String {
        guard let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) else {
            return "—"
        }
        return SizeFormatter.format(Int64(bytes))
    }
}
