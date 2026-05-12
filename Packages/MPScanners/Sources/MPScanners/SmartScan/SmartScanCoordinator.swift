import Foundation
import MPCore

public actor SmartScanCoordinator: MPCore.Scanner {
    public let category: ScanCategory = .smartScan
    private var currentResult: ScanResult?
    private var isCancelled = false

    private let systemJunk = SystemJunkScanner()
    private let trashBins = TrashBinsScanner()
    private let mailAttachments = MailAttachmentsScanner()
    private let malware = MalwareScanner()

    public init() {}

    public func scan() -> AsyncThrowingStream<ScanProgress, Error> {
        isCancelled = false
        currentResult = nil

        return AsyncThrowingStream { continuation in
            let task = Task {
                let startTime = Date()
                continuation.yield(ScanProgress(category: category, phase: .preparing))

                let moduleResults = await runAllModules(continuation: continuation)

                guard !isCancelled else {
                    continuation.finish()
                    return
                }

                continuation.yield(ScanProgress(category: category, phase: .analyzing))

                var allItems: [ScanItem] = []
                var totalBytes: Int64 = 0
                for result in moduleResults {
                    allItems.append(contentsOf: result.items)
                    totalBytes += result.totalSize
                }

                self.currentResult = ScanResult(
                    category: category,
                    items: allItems,
                    totalSize: totalBytes,
                    scanDuration: Date().timeIntervalSince(startTime)
                )

                continuation.yield(ScanProgress(
                    category: category,
                    phase: .complete,
                    itemsFound: allItems.count,
                    bytesFound: totalBytes
                ))
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public func results() -> ScanResult? { currentResult }

    public func cancel() {
        isCancelled = true
        Task {
            await systemJunk.cancel()
            await trashBins.cancel()
            await mailAttachments.cancel()
            await malware.cancel()
        }
    }

    public func reset() {
        currentResult = nil
        isCancelled = false
        Task {
            await systemJunk.reset()
            await trashBins.reset()
            await mailAttachments.reset()
            await malware.reset()
        }
    }

    // MARK: - Internal

    private func runAllModules(
        continuation: AsyncThrowingStream<ScanProgress, Error>.Continuation
    ) async -> [ScanResult] {
        await withTaskGroup(of: ScanResult?.self) { group in
            let scanners: [(any MPCore.Scanner, ScanCategory)] = [
                (systemJunk, .systemJunk),
                (trashBins, .trashBins),
                (mailAttachments, .mailAttachments),
                (malware, .malwareRemoval),
            ]

            for (scanner, cat) in scanners {
                group.addTask {
                    let stream = await scanner.scan()
                    do {
                        for try await progress in stream {
                            continuation.yield(ScanProgress(
                                category: self.category,
                                phase: .scanning,
                                currentPath: "[\(cat.rawValue)] \(progress.currentPath ?? "")",
                                itemsFound: progress.itemsFound,
                                bytesFound: progress.bytesFound
                            ))
                        }
                    } catch {
                        continuation.yield(ScanProgress(
                            category: self.category,
                            phase: .scanning,
                            currentPath: "[\(cat.rawValue)] Error: \(error.localizedDescription)"
                        ))
                    }
                    return await scanner.results()
                }
            }

            var results: [ScanResult] = []
            for await result in group {
                if let r = result { results.append(r) }
            }
            return results
        }
    }
}
