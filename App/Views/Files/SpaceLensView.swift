import SwiftUI
import MPCore
import MPUI
import MPScanners

struct SpaceLensView: View {
    @State private var scanner = SpaceLensScanner()
    @State private var phase: ScanPhase = .idle
    @State private var rootNode: DirectoryNode?
    @State private var path: [DirectoryNode] = []
    @State private var progress: ScanProgress?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            if let _ = rootNode {
                resultBody
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
            Image(systemName: ScanCategory.spaceLens.systemImage)
                .font(.system(size: 64))
                .foregroundColor(MPColors.filesAccent)

            Text("Space Lens")
                .font(MPTypography.title)

            Text("Visualise what's taking up space in your home folder as a treemap. Click any tile to drill in.")
                .font(MPTypography.body)
                .multilineTextAlignment(.center)
                .foregroundColor(MPColors.textSecondary)
                .padding(.horizontal)

            MPButton("Scan Home Folder", icon: "play.fill", style: .primary(MPColors.filesAccent)) {
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

            if let currentPath = progress?.currentPath {
                Text(currentPath)
                    .font(MPTypography.caption)
                    .foregroundColor(MPColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 400)
            }

            MPButton("Cancel", icon: "xmark", style: .secondary) {
                Task { await scanner.cancel() }
                phase = .idle
            }
        }
    }

    private var resultBody: some View {
        VStack(spacing: 12) {
            breadcrumb
            treemapBody
            footer
        }
    }

    private var displayedNode: DirectoryNode? {
        path.last ?? rootNode
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let root = rootNode {
                    crumbButton(title: root.name, isLast: path.isEmpty) {
                        path = []
                    }
                }
                ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(MPColors.textTertiary)
                    crumbButton(title: node.name, isLast: index == path.count - 1) {
                        path = Array(path.prefix(index + 1))
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func crumbButton(title: String, isLast: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(MPTypography.caption)
                .foregroundColor(isLast ? MPColors.textPrimary : MPColors.filesAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isLast ? MPColors.cardBackground : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(isLast)
    }

    private var treemapBody: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let tiles = tilesForCurrentNode(in: rect)
            if tiles.isEmpty {
                emptyOverlay
            } else {
                TreemapView(tiles: tiles) { tile in
                    drillIn(tile)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MPColors.contentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emptyOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(MPColors.textTertiary)
            Text("Nothing notable here.")
                .font(MPTypography.caption)
                .foregroundColor(MPColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if let node = displayedNode {
                Text("\(node.name) — \(SizeFormatter.format(node.size))")
                    .font(MPTypography.caption)
                    .foregroundColor(MPColors.textSecondary)
            }
            Spacer()
            if let error {
                Text(error)
                    .font(MPTypography.caption)
                    .foregroundColor(.red)
            }
            MPButton("Rescan", icon: "arrow.clockwise", style: .secondary) {
                Task { await scanner.reset() }
                rootNode = nil
                path = []
                phase = .idle
                startScan()
            }
        }
    }

    private func tilesForCurrentNode(in rect: CGRect) -> [TreemapTile] {
        guard let node = displayedNode else { return [] }
        let entries = node.children.map { child in
            TreemapEntry(label: child.name, size: child.size, url: child.url)
        }
        return Treemap.layout(entries, in: rect)
    }

    private func drillIn(_ tile: TreemapTile) {
        guard let node = displayedNode else { return }
        guard let url = tile.url,
              let child = node.children.first(where: { $0.url == url }),
              child.isDirectory,
              !child.children.isEmpty else { return }
        path.append(child)
    }

    private func startScan() {
        phase = .preparing
        error = nil
        rootNode = nil
        path = []

        Task {
            do {
                let stream = await scanner.scan()
                for try await update in stream {
                    self.progress = update
                    self.phase = update.phase
                }

                if let tree = await scanner.tree() {
                    self.rootNode = tree
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
