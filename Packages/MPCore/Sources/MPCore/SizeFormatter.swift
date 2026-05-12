import Foundation

public struct SizeFormatter {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    public static func format(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }
}
