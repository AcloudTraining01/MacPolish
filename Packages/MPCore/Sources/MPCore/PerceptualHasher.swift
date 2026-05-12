import Foundation
import CoreGraphics
import ImageIO

// Average-hash (aHash) implementation. Downscale to 8x8 grayscale, threshold
// each pixel against the mean, pack into a 64-bit value. Cheap to compute and
// resilient enough for "same image, different JPEG quality" duplicate finding.
// Note: less robust than a DCT-based pHash against brightness/contrast shifts;
// upgrade later if false-negative rate is a problem.
public enum PerceptualHasher {

    public static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tiff", "webp",
    ]

    public static func hash(url: URL) -> UInt64? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return hash(cgImage: cgImage)
    }

    public static func hash(cgImage: CGImage) -> UInt64? {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = pixels.withUnsafeMutableBytes({ buffer -> CGContext? in
            guard let base = buffer.baseAddress else { return nil }
            return CGContext(
                data: base,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        }) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        let sum = pixels.reduce(0) { $0 + Int($1) }
        let mean = sum / pixels.count
        var bits: UInt64 = 0
        for (i, p) in pixels.enumerated() where Int(p) > mean {
            bits |= UInt64(1) << UInt64(i)
        }
        return bits
    }

    public static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}
