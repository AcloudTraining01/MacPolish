import Foundation
import MPCore

public actor MailAttachmentsScanner: MPCore.Scanner {
    public let category: ScanCategory = .mailAttachments
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

                // The path pattern for Mail is typically ~/Library/Mail/V[num]/.../Attachments/
                let mailDir = NSString(string: "~/Library/Mail").expandingTildeInPath
                let mailURL = URL(fileURLWithPath: mailDir)

                if FileManager.default.fileExists(atPath: mailURL.path) {
                    let enumerator = FileManager.default.enumerator(
                        at: mailURL,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    )

                    while let itemURL = enumerator?.nextObject() as? URL {
                        guard !isCancelled else { break }

                        // Look for "Attachments" directories
                        if itemURL.lastPathComponent == "Attachments",
                           let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]),
                           let isDir = resourceValues.isDirectory, isDir {
                            
                            // Enumerate contents of this attachments directory
                            let attachmentsEnumerator = FileManager.default.enumerator(
                                at: itemURL,
                                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
                            )
                            
                            while let attachmentURL = attachmentsEnumerator?.nextObject() as? URL {
                                guard !isCancelled else { break }
                                
                                if let attrs = try? FileManager.default.attributesOfItem(atPath: attachmentURL.path),
                                   let fileType = attrs[.type] as? FileAttributeType, fileType == .typeRegular,
                                   let size = attrs[.size] as? Int64 {
                                    
                                    // Don't flag tiny files as it clutters the UI
                                    if size > 100_000 { 
                                        let modDate = attrs[.modificationDate] as? Date
                                        let item = ScanItem(
                                            path: attachmentURL,
                                            name: attachmentURL.lastPathComponent,
                                            size: size,
                                            category: category,
                                            riskLevel: .safe, // Mail handles missing attachments gracefully
                                            lastModified: modDate
                                        )
                                        foundItems.append(item)
                                        totalBytes += size
                                        
                                        if foundItems.count % 10 == 0 {
                                            continuation.yield(ScanProgress(
                                                category: category,
                                                phase: .scanning,
                                                currentPath: attachmentURL.path,
                                                itemsFound: foundItems.count,
                                                bytesFound: totalBytes
                                            ))
                                        }
                                    }
                                }
                            }
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

    public func results() -> ScanResult? { currentResult }
    public func cancel() { isCancelled = true }
    public func reset() { currentResult = nil; isCancelled = false }
}
