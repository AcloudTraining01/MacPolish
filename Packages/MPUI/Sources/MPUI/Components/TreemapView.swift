import SwiftUI
import MPCore

public struct TreemapView: View {
    private let tiles: [TreemapTile]
    private let onTap: (TreemapTile) -> Void

    public init(tiles: [TreemapTile], onTap: @escaping (TreemapTile) -> Void = { _ in }) {
        self.tiles = tiles
        self.onTap = onTap
    }

    public var body: some View {
        Canvas { context, _ in
            for tile in tiles {
                let cgRect = tile.rect
                guard cgRect.width > 1, cgRect.height > 1 else { continue }

                let inset = cgRect.insetBy(dx: 1, dy: 1)
                let path = Path(roundedRect: inset, cornerRadius: 3)
                context.fill(path, with: .color(Self.color(for: tile.label).opacity(0.85)))
                context.stroke(path, with: .color(.black.opacity(0.25)), lineWidth: 1)

                if cgRect.width > 64, cgRect.height > 34 {
                    let label = "\(tile.label)\n\(SizeFormatter.format(tile.size))"
                    let text = Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                    context.draw(
                        text,
                        in: inset.insetBy(dx: 4, dy: 4)
                    )
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    if let hit = tiles.first(where: { $0.rect.contains(value.location) }) {
                        onTap(hit)
                    }
                }
        )
    }

    private static func color(for label: String) -> Color {
        let palette: [Color] = [
            MPColors.filesAccent,
            MPColors.cleanupAccent,
            MPColors.aiAccent,
            MPColors.appsAccent,
            MPColors.speedAccent,
            MPColors.protectionAccent,
        ]
        var hasher = Hasher()
        hasher.combine(label)
        let index = abs(hasher.finalize()) % palette.count
        return palette[index]
    }
}
