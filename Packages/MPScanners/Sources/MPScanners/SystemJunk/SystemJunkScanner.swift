import Foundation
import MPCore

public actor SystemJunkScanner: MPCore.Scanner {
    public let category: ScanCategory = .systemJunk
    private var currentResult: ScanResult?
    private var isCancelled = false
    private let pathClassifier = PathClassifier()

    private let targetPaths = [
        "~/Library/Caches",
        "~/Library/Logs",
        "/Library/Caches",
        "~/Library/Developer/Xcode/DerivedData"
    ]

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

                for pathStr in targetPaths {
                    guard !isCancelled else { break }
                    
                    let resolvedPath = NSString(string: pathStr).expandingTildeInPath
                    let url = URL(fileURLWithPath: resolvedPath)
                    
                    guard FileManager.default.fileExists(atPath: url.path) else { continue }

                    let enumerator = FileManager.default.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    )

                    while let itemURL = enumerator?.nextObject() as? URL {
                        guard !isCancelled else { break }
                        
                        // We only want to delete files or empty directories, but let's 
                        // just target files for safety in v1, unless it's a known bundle.
                        guard let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]),
                              let isDir = resourceValues.isDirectory, !isDir else {
                            continue
                        }

                        let classification = pathClassifier.classify(itemURL)
                        // Only include items we deem safe or cautionary (requires helper)
                        if classification == .systemProtected || classification == .userData {
                            continue
                        }

                        if let attrs = try? FileManager.default.attributesOfItem(atPath: itemURL.path),
                           let size = attrs[.size] as? Int64 {
                            
                            // Check modification date - skip recently modified files (e.g. < 1 hour)
                            // to avoid breaking active apps.
                            let modDate = attrs[.modificationDate] as? Date
                            if let modDate = modDate, Date().timeIntervalSince(modDate) < 3600 {
                                continue
                            }

                            let risk: RiskLevel = classification == .safe ? .safe : .cautionary
                            
                            let item = ScanItem(
                                path: itemURL,
                                name: itemURL.lastPathComponent,
                                size: size,
                                category: category,
                                riskLevel: risk,
                                lastModified: modDate
                            )
                            foundItems.append(item)
                            totalBytes += size
                            
                            // Yield progress periodically
                            if foundItems.count % 100 == 0 {
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
                }

                if !isCancelled {
                    continuation.yield(ScanProgress(
                        category: category,
                        phase: .analyzing,
                        itemsFound: foundItems.count,
                        bytesFound: totalBytes
                    ))
                    
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

    public func results() -> ScanResult? { currentResult }
    public func cancel() { isCancelled = true }
    public func reset() { currentResult = nil; isCancelled = false }
}
