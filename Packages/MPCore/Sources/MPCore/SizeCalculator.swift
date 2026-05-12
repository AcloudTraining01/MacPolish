import Foundation

public enum SizeCalculator {

    public static func size(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileAllocatedSizeKey])
        if values?.isDirectory == true {
            return directorySize(at: url)
        }
        return Int64(values?.fileAllocatedSize ?? 0)
    }

    public static func directorySize(at url: URL) -> Int64 {
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        for case let fileURL as URL in enumerator {
            guard
                let values = try? fileURL.resourceValues(forKeys: [.fileAllocatedSizeKey, .isRegularFileKey]),
                values.isRegularFile == true,
                let allocated = values.fileAllocatedSize
            else { continue }
            total += Int64(allocated)
        }
        return total
    }
}
