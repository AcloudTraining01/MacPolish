import Foundation
import MPCore

public actor UpdaterScanner: MPCore.Scanner {
    public let category: ScanCategory = .updater
    private var currentResult: ScanResult?
    private var isCancelled = false

    public init() {}

    public func scan() -> AsyncThrowingStream<ScanProgress, Error> {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return scan(scopes: [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications"),
        ])
    }

    public func scan(scopes: [URL]) -> AsyncThrowingStream<ScanProgress, Error> {
        isCancelled = false
        currentResult = nil

        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(ScanProgress(category: category, phase: .preparing))
                var items: [ScanItem] = []
                let fm = FileManager.default
                for scope in scopes {
                    if isCancelled { break }
                    guard let entries = try? fm.contentsOfDirectory(
                        at: scope,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    ) else { continue }
                    for appURL in entries {
                        if isCancelled { break }
                        guard appURL.pathExtension == "app" else { continue }
                        guard let info = Self.readInfoPlist(at: appURL) else { continue }
                        let version = (info["CFBundleShortVersionString"] as? String)
                            ?? (info["CFBundleVersion"] as? String)
                            ?? "—"
                        let bundleID = (info["CFBundleIdentifier"] as? String) ?? ""
                        let displayName = (info["CFBundleDisplayName"] as? String)
                            ?? (info["CFBundleName"] as? String)
                            ?? appURL.deletingPathExtension().lastPathComponent
                        let mtime = (try? appURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                            .contentModificationDate
                        items.append(ScanItem(
                            path: appURL,
                            name: displayName,
                            size: 0,
                            category: category,
                            riskLevel: .safe,
                            lastModified: mtime,
                            explanation: "\(bundleID) — v\(version)"
                        ))
                    }
                }
                items.sort { ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast) }
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

    private static func readInfoPlist(at appURL: URL) -> [String: Any]? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}
