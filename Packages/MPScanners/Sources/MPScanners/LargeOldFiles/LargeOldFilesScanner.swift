import Foundation
import MPCore

public actor LargeOldFilesScanner: MPCore.Scanner {
    public let category: ScanCategory = .largeOldFiles
    private var currentResult: ScanResult?
    private var isCancelled = false
    private let pathClassifier = PathClassifier()

    public static let sizeThreshold: Int64 = 100_000_000
    public static let ageThresholdSeconds: TimeInterval = 365 * 24 * 3600

    public init() {}

    public func scan() -> AsyncThrowingStream<ScanProgress, Error> {
        isCancelled = false
        currentResult = nil

        return AsyncThrowingStream { continuation in
            let task = Task {
                let startTime = Date()
                continuation.yield(ScanProgress(category: category, phase: .preparing))
                continuation.yield(ScanProgress(category: category, phase: .scanning))

                let hits = await runMetadataQuery()
                guard !isCancelled else {
                    continuation.finish()
                    return
                }

                continuation.yield(ScanProgress(
                    category: category,
                    phase: .analyzing,
                    itemsFound: hits.count
                ))

                var items: [ScanItem] = []
                var totalBytes: Int64 = 0
                for hit in hits {
                    guard !isCancelled else { break }
                    let url = URL(fileURLWithPath: hit.path)
                    if Self.shouldSkip(url: url, classifier: pathClassifier) { continue }
                    items.append(ScanItem(
                        path: url,
                        name: url.lastPathComponent,
                        size: hit.size,
                        category: .largeOldFiles,
                        riskLevel: .cautionary,
                        lastModified: hit.modDate
                    ))
                    totalBytes += hit.size
                }

                if !isCancelled {
                    currentResult = ScanResult(
                        category: .largeOldFiles,
                        items: items,
                        totalSize: totalBytes,
                        scanDuration: Date().timeIntervalSince(startTime)
                    )
                    continuation.yield(ScanProgress(
                        category: category,
                        phase: .complete,
                        itemsFound: items.count,
                        bytesFound: totalBytes
                    ))
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

    private static func shouldSkip(url: URL, classifier: PathClassifier) -> Bool {
        for component in url.pathComponents {
            if component.hasSuffix(".photoslibrary") ||
               component.hasSuffix(".app") ||
               component.hasSuffix(".sparsebundle") ||
               component.hasSuffix(".framework") ||
               component.hasSuffix(".bundle") {
                return true
            }
        }
        return classifier.classify(url) == .systemProtected
    }

    private struct RawHit: Sendable {
        let path: String
        let size: Int64
        let modDate: Date?
    }

    private final class TokenHolder: @unchecked Sendable {
        var token: NSObjectProtocol?
    }

    private func runMetadataQuery() async -> [RawHit] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[RawHit], Never>) in
            DispatchQueue.main.async {
                let query = NSMetadataQuery()
                query.searchScopes = [NSMetadataQueryUserHomeScope]
                let cutoff = Date(timeIntervalSinceNow: -Self.ageThresholdSeconds) as NSDate
                query.predicate = NSPredicate(
                    format: "kMDItemFSSize > %lld AND kMDItemContentModificationDate < %@",
                    Self.sizeThreshold,
                    cutoff
                )

                let holder = TokenHolder()
                holder.token = NotificationCenter.default.addObserver(
                    forName: .NSMetadataQueryDidFinishGathering,
                    object: query,
                    queue: .main
                ) { _ in
                    if let token = holder.token {
                        NotificationCenter.default.removeObserver(token)
                    }
                    query.disableUpdates()
                    var hits: [RawHit] = []
                    for index in 0..<query.resultCount {
                        guard
                            let item = query.result(at: index) as? NSMetadataItem,
                            let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                            let sizeNumber = item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber
                        else { continue }
                        let modDate = item.value(forAttribute: NSMetadataItemContentModificationDateKey) as? Date
                        hits.append(RawHit(path: path, size: sizeNumber.int64Value, modDate: modDate))
                    }
                    query.stop()
                    continuation.resume(returning: hits)
                }

                query.start()
            }
        }
    }
}
