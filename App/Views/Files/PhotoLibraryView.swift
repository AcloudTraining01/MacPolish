import SwiftUI
import AppKit
import MPCore
import MPUI
import MPScanners

struct PhotoLibraryView: View {
    @State private var scanner = PhotoLibraryScanner()
    @State private var phase: ScanPhase = .idle
    @State private var result: ScanResult?
    @State private var progress: ScanProgress?
    @State private var error: String?
    @State private var access: PhotoLibraryScanner.AccessState = PhotoLibraryScanner.authorizationStatus()
    @State private var showConfirmation = false
    @State private var isDeleting = false

    var body: some View {
        VStack {
            switch access {
            case .granted, .limited:
                grantedContent
            case .denied, .restricted:
                deniedView
            case .unknown:
                requestView
            }
        }
        .padding()
    }

    private var requestView: some View {
        VStack(spacing: 20) {
            Image(systemName: ScanCategory.photoLibrary.systemImage)
                .font(.system(size: 64))
                .foregroundColor(MPColors.filesAccent)
            Text("Photo Library Cleaner")
                .font(MPTypography.title)
            Text("MacPolish needs access to your Photos library to find old screenshots that you may want to clean up. Your photos are never uploaded or modified.")
                .font(MPTypography.body)
                .multilineTextAlignment(.center)
                .foregroundColor(MPColors.textSecondary)
                .padding(.horizontal)
            MPButton("Grant Access", icon: "checkmark.shield", style: .primary(MPColors.filesAccent)) {
                Task {
                    access = await PhotoLibraryScanner.requestAuthorization()
                }
            }
        }
    }

    private var deniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 56))
                .foregroundColor(MPColors.warning)
            Text("Photos Access Denied")
                .font(MPTypography.title)
            Text("Enable Photos access for MacPolish in System Settings to scan your library.")
                .font(MPTypography.body)
                .multilineTextAlignment(.center)
                .foregroundColor(MPColors.textSecondary)
                .padding(.horizontal)
            MPButton("Open System Settings", icon: "gearshape", style: .secondary) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    @ViewBuilder
    private var grantedContent: some View {
        if let result {
            resultView(result)
        } else if phase == .scanning || phase == .analyzing || phase == .preparing {
            scanningView
        } else {
            startView
        }
    }

    private var startView: some View {
        VStack(spacing: 20) {
            Image(systemName: ScanCategory.photoLibrary.systemImage)
                .font(.system(size: 64))
                .foregroundColor(MPColors.filesAccent)
            Text("Photo Library Cleaner")
                .font(MPTypography.title)
            Text("Find screenshots older than six months that you can delete from your Photos library.")
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
                Text("Found \(items) screenshot\(items == 1 ? "" : "s")")
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
                Text("Old Screenshots")
                    .font(MPTypography.title2)
                Spacer()
                Text(SizeFormatter.format(res.totalSize))
                    .font(MPTypography.title2)
                    .foregroundColor(MPColors.filesAccent)
            }

            if res.items.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(res.items.sorted(by: { ($0.lastModified ?? .distantPast) < ($1.lastModified ?? .distantPast) })) { item in
                        ItemListRow(item: item, onToggle: { _ in })
                    }
                }
                .listStyle(.inset)
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
                    isDeleting ? "Deleting…" : "Delete From Photos",
                    icon: "trash",
                    style: .primary(MPColors.filesAccent)
                ) {
                    showConfirmation = true
                }
                .disabled(res.items.isEmpty || isDeleting)
            }
        }
        .confirmationDialog(
            "Delete \(res.items.count) screenshot\(res.items.count == 1 ? "" : "s") from Photos?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Continue", role: .destructive) {
                runDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Photos will show its own confirmation prompt. Deletion moves the items to the Photos Recently Deleted album, where they remain recoverable for 30 days.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundColor(MPColors.filesAccent.opacity(0.6))
            Text("No old screenshots found.")
                .font(MPTypography.headline)
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

    private func runDelete() {
        isDeleting = true
        error = nil
        Task {
            do {
                let ids = await scanner.capturedAssetLocalIdentifiers()
                try await scanner.deleteAssets(localIdentifiers: ids)
                result = nil
                phase = .idle
            } catch {
                self.error = "Delete failed: \(error.localizedDescription)"
            }
            isDeleting = false
        }
    }
}
