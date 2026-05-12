import Foundation
import MPCore

public actor TrashBinsScanner: MPCore.Scanner {
    public let category: ScanCategory = .trashBins
    private var currentResult: ScanResult?
    private var isCancelled = false

    public init() {}

    public func scan() -> AsyncThrowingStream<ScanProgress, Error> {
        isCancelled = false
        currentResult = nil
        
        return AsyncThrowingStream { continuation in
            let task = Task {
                var foundItems: [ScanItem] = []
                var totalBytes: Int64 = 0
                let startTime = Date()

                continuation.yield(ScanProgress(category: category, phase: .preparing))

                let trashPath = NSString(string: "~/.Trash").expandingTildeInPath
                let url = URL(fileURLWithPath: trashPath)
                
                if FileManager.default.fileExists(atPath: url.path) {
                    let enumerator = FileManager.default.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    )

                    while let itemURL = enumerator?.nextObject() as? URL {
                        guard !isCancelled else { break }
                        
                        // In trash, we can delete directories, but let's just count files for size
                        // Actually, enumerating the trash gives us everything.
                        
                        // We only want to add the top-level items in the trash to the UI, 
                        // but we need to calculate total size. For simplicity in v1, 
                        // let's just list top-level items and compute their sizes.
                        
                        if itemURL.deletingLastPathComponent() == url {
                            // It's a top level item
                            let size = self.calculateSize(of: itemURL)
                            let attrs = try? FileManager.default.attributesOfItem(atPath: itemURL.path)
                            let modDate = attrs?[.modificationDate] as? Date
                            
                            let item = ScanItem(
                                path: itemURL,
                                name: itemURL.lastPathComponent,
                                size: size,
                                category: category,
                                riskLevel: .safe, // Safe to delete trash
                                lastModified: modDate
                            )
                            foundItems.append(item)
                            totalBytes += size
                            
                            continuation.yield(ScanProgress(
                                category: category,
                                phase: .scanning,
                                currentPath: itemURL.path,
                                itemsFound: foundItems.count,
                                bytesFound: totalBytes
                            ))
                        }
                    }
                }

                if !isCancelled {
                    self.currentResult = ScanResult(
                        category: category,
                        items: foundItems,
                        totalSize: totalBytes,
                        scanDuration: Date().timeIntervalSince(startTime)
                    )
                    continuation.yield(ScanProgress(category: category, phase: .complete, itemsFound: foundItems.count, bytesFound: totalBytes))
                }
                continuation.finish()
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func calculateSize(of url: URL) -> Int64 {
        var size: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileType = attrs[.type] as? FileAttributeType {
            if fileType == .typeDirectory {
                if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                    for case let fileURL as URL in enumerator {
                        if let fileAttrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                           let fileSize = fileAttrs[.size] as? Int64 {
                            size += fileSize
                        }
                    }
                }
            } else if let fileSize = attrs[.size] as? Int64 {
                size = fileSize
            }
        }
        return size
    }

    public func results() -> ScanResult? { currentResult }
    public func cancel() { isCancelled = true }
    public func reset() { currentResult = nil; isCancelled = false }
}
