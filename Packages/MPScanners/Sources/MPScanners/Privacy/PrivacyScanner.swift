import Foundation
import MPCore

public actor PrivacyScanner: MPCore.Scanner {
    public let category: ScanCategory = .privacy
    private var currentResult: ScanResult?
    private var isCancelled = false

    public init() {}

    struct Target {
        let url: URL
        let kind: String
        let owningProcess: String
    }

    private static func defaultTargets() -> [Target] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var targets: [Target] = []

        let safari = home.appendingPathComponent("Library/Safari")
        for name in ["History.db", "History.db-wal", "History.db-shm", "Downloads.plist"] {
            targets.append(.init(
                url: safari.appendingPathComponent(name),
                kind: "Safari history",
                owningProcess: "Safari"
            ))
        }

        let chromeRoot = home.appendingPathComponent("Library/Application Support/Google/Chrome/Default")
        for name in ["History", "History-journal", "Visited Links"] {
            targets.append(.init(
                url: chromeRoot.appendingPathComponent(name),
                kind: "Chrome history",
                owningProcess: "Google Chrome"
            ))
        }

        let firefoxProfiles = home.appendingPathComponent("Library/Application Support/Firefox/Profiles")
        if let profiles = try? FileManager.default.contentsOfDirectory(
            at: firefoxProfiles,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for profile in profiles {
                targets.append(.init(
                    url: profile.appendingPathComponent("places.sqlite"),
                    kind: "Firefox history",
                    owningProcess: "firefox"
                ))
            }
        }

        let quickLook = URL(fileURLWithPath: "/private/var/folders")
        if let scanned = try? FileManager.default.contentsOfDirectory(
            at: quickLook,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for outer in scanned {
                let inner = try? FileManager.default.contentsOfDirectory(at: outer, includingPropertiesForKeys: nil)
                for mid in inner ?? [] {
                    let candidate = mid.appendingPathComponent("C/com.apple.QuickLook.thumbnailcache")
                    if FileManager.default.fileExists(atPath: candidate.path) {
                        targets.append(.init(
                            url: candidate,
                            kind: "Quick Look thumbnails",
                            owningProcess: "quicklookd"
                        ))
                    }
                }
            }
        }

        return targets
    }

    public func scan() -> AsyncThrowingStream<ScanProgress, Error> {
        scan(targets: Self.defaultTargets())
    }

    func scan(targets: [Target]) -> AsyncThrowingStream<ScanProgress, Error> {
        isCancelled = false
        currentResult = nil
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(ScanProgress(category: category, phase: .preparing))
                var items: [ScanItem] = []
                let fm = FileManager.default
                for target in targets {
                    if isCancelled { break }
                    guard fm.fileExists(atPath: target.url.path) else { continue }
                    let size = SizeCalculator.size(of: target.url)
                    let mtime = (try? target.url.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate
                    let processOpen = Self.isProcessRunning(named: target.owningProcess)
                    items.append(ScanItem(
                        path: target.url,
                        name: target.url.lastPathComponent,
                        size: size,
                        category: category,
                        riskLevel: processOpen ? .cautionary : .safe,
                        lastModified: mtime,
                        explanation: processOpen
                            ? "\(target.kind) — \(target.owningProcess) running, do not delete"
                            : target.kind
                    ))
                }
                let total = items.reduce(Int64(0)) { $0 + $1.size }
                currentResult = ScanResult(
                    category: category,
                    items: items,
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

    // Process check via `pgrep` — avoids parsing `ps`/`lsof` output. Returns true if
    // pgrep finds at least one process whose name matches. Conservative on failure
    // (returns false), so a missing/blocked pgrep won't flag every browser DB as
    // unsafe; the user is still warned via the .cautionary risk level in the UI
    // when the process is detected.
    private static func isProcessRunning(named name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-xi", name]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
