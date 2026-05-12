import Foundation
import MPCore

public actor OptimizationScanner: MPCore.Scanner {
    public let category: ScanCategory = .optimization
    private var currentResult: ScanResult?
    private var isCancelled = false

    public init() {}

    private static let locations: [(URL, String)] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            (home.appendingPathComponent("Library/LaunchAgents"), "User launch agent"),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), "System launch agent"),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), "System launch daemon"),
        ]
    }()

    public func scan() -> AsyncThrowingStream<ScanProgress, Error> {
        scan(locations: Self.locations)
    }

    func scan(locations: [(URL, String)]) -> AsyncThrowingStream<ScanProgress, Error> {
        isCancelled = false
        currentResult = nil
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(ScanProgress(category: category, phase: .preparing))
                var items: [ScanItem] = []
                let fm = FileManager.default
                for (root, kind) in locations {
                    if isCancelled { break }
                    guard let entries = try? fm.contentsOfDirectory(
                        at: root,
                        includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                        options: [.skipsHiddenFiles]
                    ) else { continue }
                    for entry in entries {
                        if isCancelled { break }
                        guard entry.pathExtension == "plist" else { continue }
                        let info = Self.readPlist(at: entry)
                        let label = (info?["Label"] as? String) ?? entry.deletingPathExtension().lastPathComponent
                        let program = (info?["Program"] as? String)
                            ?? ((info?["ProgramArguments"] as? [String])?.first)
                            ?? "—"
                        let runAtLoad = (info?["RunAtLoad"] as? Bool) ?? false
                        let size = (try? entry.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        let mtime = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                            .contentModificationDate
                        let explanation = "\(kind) — runs \(program)\(runAtLoad ? " (at login)" : "")"
                        items.append(ScanItem(
                            path: entry,
                            name: label,
                            size: Int64(size),
                            category: category,
                            riskLevel: runAtLoad ? .cautionary : .safe,
                            lastModified: mtime,
                            explanation: explanation
                        ))
                    }
                }
                items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                currentResult = ScanResult(
                    category: category,
                    items: items,
                    totalSize: 0,
                    scanDuration: 0
                )
                continuation.yield(ScanProgress(
                    category: category,
                    phase: .complete,
                    itemsFound: items.count
                ))
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func results() -> ScanResult? { currentResult }
    public func cancel() { isCancelled = true }
    public func reset() { currentResult = nil; isCancelled = false }

    private static func readPlist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}
