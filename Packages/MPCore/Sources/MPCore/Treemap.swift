import Foundation
import CoreGraphics

public struct TreemapEntry: Sendable, Hashable {
    public let label: String
    public let size: Int64
    public let url: URL?

    public init(label: String, size: Int64, url: URL? = nil) {
        self.label = label
        self.size = size
        self.url = url
    }
}

public struct TreemapTile: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let label: String
    public let size: Int64
    public let rect: CGRect
    public let url: URL?

    public init(id: UUID = UUID(), label: String, size: Int64, rect: CGRect, url: URL? = nil) {
        self.id = id
        self.label = label
        self.size = size
        self.rect = rect
        self.url = url
    }
}

// Squarified treemap (Bruls / Huijbregts / van Wijk).
public enum Treemap {

    public static func layout(_ entries: [TreemapEntry], in rect: CGRect) -> [TreemapTile] {
        let positives = entries.filter { $0.size > 0 }
        guard !positives.isEmpty, rect.width > 0, rect.height > 0 else { return [] }

        let totalBytes = positives.reduce(Int64(0)) { $0 + $1.size }
        let area = Double(rect.width) * Double(rect.height)
        let unitsPerByte = area / Double(totalBytes)

        let sorted = positives.sorted { $0.size > $1.size }
        let scaled = sorted.map { Double($0.size) * unitsPerByte }

        var output: [TreemapTile] = []
        var remainingEntries = sorted
        var remainingScaled = scaled
        var rowEntries: [TreemapEntry] = []
        var rowScaled: [Double] = []
        var remainingRect = rect

        while !remainingEntries.isEmpty {
            let next = remainingEntries[0]
            let nextScaled = remainingScaled[0]
            let w = Double(min(remainingRect.width, remainingRect.height))
            let candidate = rowScaled + [nextScaled]

            if rowScaled.isEmpty || worstAspect(sizes: candidate, w: w) <= worstAspect(sizes: rowScaled, w: w) {
                rowEntries.append(next)
                rowScaled.append(nextScaled)
                remainingEntries.removeFirst()
                remainingScaled.removeFirst()
            } else {
                remainingRect = placeRow(entries: rowEntries, scaled: rowScaled, in: remainingRect, output: &output)
                rowEntries.removeAll(keepingCapacity: true)
                rowScaled.removeAll(keepingCapacity: true)
            }
        }
        if !rowEntries.isEmpty {
            _ = placeRow(entries: rowEntries, scaled: rowScaled, in: remainingRect, output: &output)
        }
        return output
    }

    static func worstAspect(sizes: [Double], w: Double) -> Double {
        guard !sizes.isEmpty, w > 0 else { return .infinity }
        let sum = sizes.reduce(0, +)
        guard sum > 0, let maxS = sizes.max(), let minS = sizes.min(), minS > 0 else {
            return .infinity
        }
        let wSq = w * w
        let sSq = sum * sum
        return max(wSq * maxS / sSq, sSq / (wSq * minS))
    }

    private static func placeRow(
        entries: [TreemapEntry],
        scaled: [Double],
        in rect: CGRect,
        output: inout [TreemapTile]
    ) -> CGRect {
        let sum = scaled.reduce(0, +)
        guard sum > 0 else { return rect }

        let horizontal = rect.width >= rect.height
        let w = Double(min(rect.width, rect.height))
        let thickness = CGFloat(sum / w)

        if horizontal {
            var y = rect.minY
            for (i, entry) in entries.enumerated() {
                let h = CGFloat(scaled[i] / sum) * rect.height
                output.append(TreemapTile(
                    label: entry.label,
                    size: entry.size,
                    rect: CGRect(x: rect.minX, y: y, width: thickness, height: h),
                    url: entry.url
                ))
                y += h
            }
            return CGRect(
                x: rect.minX + thickness,
                y: rect.minY,
                width: rect.width - thickness,
                height: rect.height
            )
        } else {
            var x = rect.minX
            for (i, entry) in entries.enumerated() {
                let wd = CGFloat(scaled[i] / sum) * rect.width
                output.append(TreemapTile(
                    label: entry.label,
                    size: entry.size,
                    rect: CGRect(x: x, y: rect.minY, width: wd, height: thickness),
                    url: entry.url
                ))
                x += wd
            }
            return CGRect(
                x: rect.minX,
                y: rect.minY + thickness,
                width: rect.width,
                height: rect.height - thickness
            )
        }
    }
}
