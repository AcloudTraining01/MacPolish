import Foundation
import MPCore

public actor SpaceLensScanner: MPCore.Scanner {
    public let category: ScanCategory = .spaceLens
    private var currentResult: ScanResult?
    private var rootNode: DirectoryNode?
    private var isCancelled = false
    private let pathClassifier = PathClassifier()

    public static let maxDepth: Int = 4
    public static let minLeafSize: Int64 = 1_048_576

    private static let opaqueBundleSuffixes: [String] = [
        ".app", ".photoslibrary", ".sparsebundle", ".framework", ".bundle"
    ]

    public init() {}

    public func scan() -> AsyncThrowingStream<ScanProgress, Error> {
        scan(at: FileManager.default.homeDirectoryForCurrentUser)
    }

    public func scan(at root: URL) -> AsyncThrowingStream<ScanProgress, Error> {
        isCancelled = false
        currentResult = nil
        rootNode = nil

        return AsyncThrowingStream { continuation in
            let task = Task {
                let startTime = Date()
                continuation.yield(ScanProgress(category: category, phase: .preparing))
                continuation.yield(ScanProgress(
                    category: category,
                    phase: .scanning,
                    currentPath: root.path
                ))

                let node = buildNode(at: root, depth: 0)
                guard !isCancelled else {
                    continuation.finish()
                    return
                }

                rootNode = node

                let items = node.children.map { child in
                    ScanItem(
                        path: child.url,
                        name: child.name,
                        size: child.size,
                        category: category,
                        riskLevel: .cautionary,
                        lastModified: nil
                    )
                }

                currentResult = ScanResult(
                    category: category,
                    items: items,
                    totalSize: node.size,
                    scanDuration: Date().timeIntervalSince(startTime)
                )

                continuation.yield(ScanProgress(
                    category: category,
                    phase: .complete,
                    itemsFound: items.count,
                    bytesFound: node.size
                ))
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public func tree() -> DirectoryNode? { rootNode }
    public func results() -> ScanResult? { currentResult }
    public func cancel() { isCancelled = true }
    public func reset() {
        currentResult = nil
        rootNode = nil
        isCancelled = false
    }

    private func buildNode(at url: URL, depth: Int) -> DirectoryNode {
        let name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent

        if pathClassifier.classify(url) == .systemProtected {
            return DirectoryNode(url: url, name: name, size: 0, isDirectory: true)
        }

        let path = url.path
        if path.hasPrefix("/Volumes/.timemachine") || path.contains("/.timemachine/") {
            return DirectoryNode(url: url, name: name, size: 0, isDirectory: true)
        }

        if Self.isOpaqueBundle(name) {
            let size = SizeCalculator.size(of: url)
            return DirectoryNode(url: url, name: name, size: size, isDirectory: false)
        }

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        let isDir = values?.isDirectory ?? false
        if !isDir {
            let size = SizeCalculator.size(of: url)
            return DirectoryNode(url: url, name: name, size: size, isDirectory: false)
        }

        if depth >= Self.maxDepth {
            let size = SizeCalculator.directorySize(at: url)
            return DirectoryNode(url: url, name: name, size: size, isDirectory: true)
        }

        let fm = FileManager.default
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return DirectoryNode(url: url, name: name, size: 0, isDirectory: true)
        }

        var children: [DirectoryNode] = []
        var totalSize: Int64 = 0
        for child in entries {
            if isCancelled { break }
            let childNode = buildNode(at: child, depth: depth + 1)
            children.append(childNode)
            totalSize += childNode.size
        }

        let filtered = children.filter { $0.size >= Self.minLeafSize }
        return DirectoryNode(
            url: url,
            name: name,
            size: totalSize,
            isDirectory: true,
            children: filtered.sorted(by: { $0.size > $1.size })
        )
    }

    private static func isOpaqueBundle(_ name: String) -> Bool {
        opaqueBundleSuffixes.contains(where: { name.hasSuffix($0) })
    }
}
