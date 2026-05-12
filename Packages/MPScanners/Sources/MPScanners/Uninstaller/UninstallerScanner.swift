import Foundation
import MPCore

public struct Uninstallable: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let appURL: URL
    public let displayName: String
    public let bundleID: String
    public let appSize: Int64
    public let leftovers: [Leftover]

    public var totalSize: Int64 {
        appSize + leftovers.reduce(0) { $0 + $1.size }
    }

    public init(
        id: UUID = UUID(),
        appURL: URL,
        displayName: String,
        bundleID: String,
        appSize: Int64,
        leftovers: [Leftover]
    ) {
        self.id = id
        self.appURL = appURL
        self.displayName = displayName
        self.bundleID = bundleID
        self.appSize = appSize
        self.leftovers = leftovers
    }

    public static func == (lhs: Uninstallable, rhs: Uninstallable) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public struct Leftover: Sendable, Hashable {
        public let url: URL
        public let size: Int64
        public let kind: String

        public init(url: URL, size: Int64, kind: String) {
            self.url = url
            self.size = size
            self.kind = kind
        }
    }
}

public actor UninstallerScanner: MPCore.Scanner {
    public let category: ScanCategory = .uninstaller
    private var currentResult: ScanResult?
    private var uninstallables: [Uninstallable] = []
    private var isCancelled = false
    private let pathClassifier = PathClassifier()

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
        uninstallables = []

        return AsyncThrowingStream { continuation in
            let task = Task {
                let startTime = Date()
                continuation.yield(ScanProgress(category: category, phase: .preparing))

                let home = FileManager.default.homeDirectoryForCurrentUser
                let leftoverRoots: [(URL, String)] = [
                    (home.appendingPathComponent("Library/Application Support"), "Application Support"),
                    (home.appendingPathComponent("Library/Preferences"), "Preferences"),
                    (home.appendingPathComponent("Library/Caches"), "Caches"),
                    (home.appendingPathComponent("Library/Containers"), "Containers"),
                    (home.appendingPathComponent("Library/Group Containers"), "Group Containers"),
                    (home.appendingPathComponent("Library/Saved Application State"), "Saved State"),
                    (home.appendingPathComponent("Library/LaunchAgents"), "Launch Agents"),
                    (home.appendingPathComponent("Library/Logs"), "Logs"),
                    (home.appendingPathComponent("Library/HTTPStorages"), "Web Storage"),
                    (home.appendingPathComponent("Library/WebKit"), "WebKit Data"),
                ]

                var collected: [Uninstallable] = []

                for scope in scopes {
                    if isCancelled { break }
                    guard let entries = try? FileManager.default.contentsOfDirectory(
                        at: scope,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    ) else { continue }

                    for appURL in entries {
                        if isCancelled { break }
                        guard appURL.pathExtension == "app" else { continue }
                        guard let bundleID = Self.readBundleID(at: appURL) else { continue }
                        let displayName = Self.readDisplayName(at: appURL)
                            ?? appURL.deletingPathExtension().lastPathComponent
                        let appSize = SizeCalculator.directorySize(at: appURL)

                        var leftovers: [Uninstallable.Leftover] = []
                        for (root, kind) in leftoverRoots {
                            if isCancelled { break }
                            for candidate in Self.leftoverCandidates(at: root, bundleID: bundleID) {
                                let size = SizeCalculator.size(of: candidate)
                                if size > 0 {
                                    leftovers.append(.init(url: candidate, size: size, kind: kind))
                                }
                            }
                        }

                        continuation.yield(ScanProgress(
                            category: category,
                            phase: .scanning,
                            currentPath: appURL.path,
                            itemsFound: collected.count + 1
                        ))

                        collected.append(Uninstallable(
                            appURL: appURL,
                            displayName: displayName,
                            bundleID: bundleID,
                            appSize: appSize,
                            leftovers: leftovers
                        ))
                    }
                }

                if !isCancelled {
                    uninstallables = collected.sorted { $0.totalSize > $1.totalSize }

                    let items = uninstallables.map { unit -> ScanItem in
                        let leftoverCount = unit.leftovers.count
                        let explanation = "\(unit.bundleID) — \(leftoverCount) leftover\(leftoverCount == 1 ? "" : "s")"
                        return ScanItem(
                            path: unit.appURL,
                            name: unit.displayName,
                            size: unit.totalSize,
                            category: .uninstaller,
                            riskLevel: .cautionary,
                            lastModified: nil,
                            explanation: explanation
                        )
                    }
                    let total = items.reduce(Int64(0)) { $0 + $1.size }
                    currentResult = ScanResult(
                        category: category,
                        items: items,
                        totalSize: total,
                        scanDuration: Date().timeIntervalSince(startTime)
                    )
                    continuation.yield(ScanProgress(
                        category: category,
                        phase: .complete,
                        itemsFound: items.count,
                        bytesFound: total
                    ))
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public func uninstallableList() -> [Uninstallable] { uninstallables }
    public func results() -> ScanResult? { currentResult }
    public func cancel() { isCancelled = true }
    public func reset() {
        currentResult = nil
        uninstallables = []
        isCancelled = false
    }

    // MARK: - Private

    private static func readBundleID(at appURL: URL) -> String? {
        readInfoPlist(at: appURL)?["CFBundleIdentifier"] as? String
    }

    private static func readDisplayName(at appURL: URL) -> String? {
        let info = readInfoPlist(at: appURL)
        return (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
    }

    private static func readInfoPlist(at appURL: URL) -> [String: Any]? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL) else { return nil }
        return (try? PropertyListSerialization.propertyList(
            from: data, format: nil
        )) as? [String: Any]
    }

    private static func leftoverCandidates(at root: URL, bundleID: String) -> [URL] {
        let fm = FileManager.default
        let suffixes = ["", ".plist", ".savedState", ".binarycookies"]
        var candidates: [URL] = []
        for suffix in suffixes {
            let candidate = root.appendingPathComponent("\(bundleID)\(suffix)")
            if fm.fileExists(atPath: candidate.path) {
                candidates.append(candidate)
            }
        }
        return candidates
    }
}
