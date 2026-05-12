import Foundation
import MPCore

public actor ExtensionsScanner: MPCore.Scanner {
    public let category: ScanCategory = .extensions
    private var currentResult: ScanResult?
    private var isCancelled = false

    public init() {}

    private static let locations: [(URL, String, String)] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            (URL(fileURLWithPath: "/Library/Spotlight"), "Spotlight", "mdimporter"),
            (home.appendingPathComponent("Library/Spotlight"), "Spotlight (user)", "mdimporter"),
            (URL(fileURLWithPath: "/Library/QuickLook"), "Quick Look", "qlgenerator"),
            (home.appendingPathComponent("Library/QuickLook"), "Quick Look (user)", "qlgenerator"),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), "Launch Agent", "plist"),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), "Launch Daemon", "plist"),
            (home.appendingPathComponent("Library/LaunchAgents"), "Launch Agent (user)", "plist"),
            (URL(fileURLWithPath: "/Library/PreferencePanes"), "Preference Pane", "prefPane"),
            (home.appendingPathComponent("Library/PreferencePanes"), "Preference Pane (user)", "prefPane"),
        ]
    }()

    public func scan() -> AsyncThrowingStream<ScanProgress, Error> {
        scan(locations: Self.locations)
    }

    func scan(locations: [(URL, String, String)]) -> AsyncThrowingStream<ScanProgress, Error> {
        isCancelled = false
        currentResult = nil
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(ScanProgress(category: category, phase: .preparing))
                var items: [ScanItem] = []
                let fm = FileManager.default
                for (root, kind, ext) in locations {
                    if isCancelled { break }
                    guard let entries = try? fm.contentsOfDirectory(
                        at: root,
                        includingPropertiesForKeys: [.contentModificationDateKey],
                        options: [.skipsHiddenFiles]
                    ) else { continue }
                    for entry in entries {
                        if isCancelled { break }
                        guard entry.pathExtension == ext else { continue }
                        let size = SizeCalculator.size(of: entry)
                        let mtime = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
                            .contentModificationDate
                        items.append(ScanItem(
                            path: entry,
                            name: entry.lastPathComponent,
                            size: size,
                            category: category,
                            riskLevel: .cautionary,
                            lastModified: mtime,
                            explanation: kind
                        ))
                    }
                }
                let total = items.reduce(Int64(0)) { $0 + $1.size }
                currentResult = ScanResult(
                    category: category,
                    items: items.sorted { $0.size > $1.size },
                    totalSize: total,
                    scanDuration: 0
                )
                continuation.yield(ScanProgress(
                    category: category,
                    phase: .complete,
                    itemsFound: items.count,
                    bytesFound: total
                ))
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func results() -> ScanResult? { currentResult }
    public func cancel() { isCancelled = true }
    public func reset() { currentResult = nil; isCancelled = false }
}
