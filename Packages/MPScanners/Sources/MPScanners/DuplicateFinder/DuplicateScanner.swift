import Foundation
import CryptoKit
import MPCore

public enum DuplicateMode: Sendable {
    case exact
    case perceptual
}

public actor DuplicateScanner: MPCore.Scanner {
    public let category: ScanCategory = .duplicateFinder
    private var currentResult: ScanResult?
    private var isCancelled = false
    private let pathClassifier = PathClassifier()

    public static let minFileSize: Int64 = 4096
    public static let perceptualHammingThreshold: Int = 8
    private static let chunkSize = 64 * 1024

    private static let opaqueBundleSuffixes: [String] = [
        ".app", ".photoslibrary", ".sparsebundle", ".framework", ".bundle"
    ]

    public init() {}

    public func scan() -> AsyncThrowingStream<ScanProgress, Error> {
        scan(scopes: defaultScopes(), mode: .exact)
    }

    public func scan(scopes: [URL]) -> AsyncThrowingStream<ScanProgress, Error> {
        scan(scopes: scopes, mode: .exact)
    }

    public func scan(scopes: [URL], mode: DuplicateMode) -> AsyncThrowingStream<ScanProgress, Error> {
        isCancelled = false
        currentResult = nil

        return AsyncThrowingStream { continuation in
            let task = Task {
                let startTime = Date()
                continuation.yield(ScanProgress(category: category, phase: .preparing))
                switch mode {
                case .exact:
                    await runExact(scopes: scopes, startTime: startTime, continuation: continuation)
                case .perceptual:
                    await runPerceptual(scopes: scopes, startTime: startTime, continuation: continuation)
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

    // MARK: - Exact

    private func runExact(
        scopes: [URL],
        startTime: Date,
        continuation: AsyncThrowingStream<ScanProgress, Error>.Continuation
    ) async {
        var bySize: [Int64: [FileCandidate]] = [:]
        for scope in scopes {
            if isCancelled { return }
            enumerateCandidates(in: scope, includeImagesOnly: false, into: &bySize)
        }
        if isCancelled { return }

        let collisions = bySize.values.filter { $0.count > 1 }
        let totalToHash = collisions.reduce(0) { $0 + $1.count }
        var hashed = 0
        var byHash: [String: [FileCandidate]] = [:]

        continuation.yield(ScanProgress(category: category, phase: .scanning, itemsFound: 0))

        for group in collisions {
            if isCancelled { return }
            for file in group {
                if isCancelled { return }
                guard let hash = Self.hashFile(at: file.url) else {
                    hashed += 1
                    continue
                }
                byHash[hash, default: []].append(file)
                hashed += 1
                if hashed % 20 == 0 || hashed == totalToHash {
                    continuation.yield(ScanProgress(
                        category: category,
                        phase: .scanning,
                        currentPath: file.url.path,
                        itemsFound: hashed
                    ))
                }
            }
        }
        if isCancelled { return }

        continuation.yield(ScanProgress(category: category, phase: .analyzing))

        var items: [ScanItem] = []
        var totalBytes: Int64 = 0
        for dupes in byHash.values where dupes.count > 1 {
            let sorted = dupes.sorted { canonicalOrder(a: $0, b: $1) }
            guard let canonical = sorted.first else { continue }
            for dup in sorted.dropFirst() {
                items.append(ScanItem(
                    path: dup.url,
                    name: dup.url.lastPathComponent,
                    size: dup.size,
                    category: .duplicateFinder,
                    riskLevel: .safe,
                    lastModified: dup.modDate,
                    explanation: "Duplicate of \(canonical.url.path)"
                ))
                totalBytes += dup.size
            }
        }

        currentResult = ScanResult(
            category: category,
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

    // MARK: - Perceptual

    private func runPerceptual(
        scopes: [URL],
        startTime: Date,
        continuation: AsyncThrowingStream<ScanProgress, Error>.Continuation
    ) async {
        var bySize: [Int64: [FileCandidate]] = [:]
        for scope in scopes {
            if isCancelled { return }
            enumerateCandidates(in: scope, includeImagesOnly: true, into: &bySize)
        }
        if isCancelled { return }

        // Flatten all image candidates and hash each.
        let allCandidates = bySize.values.flatMap { $0 }
        var fingerprints: [(file: FileCandidate, hash: UInt64)] = []
        fingerprints.reserveCapacity(allCandidates.count)
        var processed = 0
        let total = allCandidates.count

        continuation.yield(ScanProgress(category: category, phase: .scanning, itemsFound: 0))

        for candidate in allCandidates {
            if isCancelled { return }
            if let hash = PerceptualHasher.hash(url: candidate.url) {
                fingerprints.append((candidate, hash))
            }
            processed += 1
            if processed % 10 == 0 || processed == total {
                continuation.yield(ScanProgress(
                    category: category,
                    phase: .scanning,
                    currentPath: candidate.url.path,
                    itemsFound: processed
                ))
            }
        }
        if isCancelled { return }

        continuation.yield(ScanProgress(category: category, phase: .analyzing))

        // Greedy clustering by Hamming distance.
        var clusters: [[Int]] = []
        var assigned = [Bool](repeating: false, count: fingerprints.count)
        for i in 0..<fingerprints.count {
            if isCancelled { return }
            if assigned[i] { continue }
            var cluster: [Int] = [i]
            assigned[i] = true
            for j in (i + 1)..<fingerprints.count {
                if assigned[j] { continue }
                let dist = PerceptualHasher.hammingDistance(fingerprints[i].hash, fingerprints[j].hash)
                if dist <= Self.perceptualHammingThreshold {
                    cluster.append(j)
                    assigned[j] = true
                }
            }
            if cluster.count > 1 { clusters.append(cluster) }
        }

        var items: [ScanItem] = []
        var totalBytes: Int64 = 0
        for cluster in clusters {
            let candidates = cluster.map { fingerprints[$0].file }
            let sorted = candidates.sorted { canonicalOrder(a: $0, b: $1) }
            guard let canonical = sorted.first else { continue }
            for dup in sorted.dropFirst() {
                items.append(ScanItem(
                    path: dup.url,
                    name: dup.url.lastPathComponent,
                    size: dup.size,
                    category: .duplicateFinder,
                    riskLevel: .cautionary,
                    lastModified: dup.modDate,
                    explanation: "Looks like \(canonical.url.path)"
                ))
                totalBytes += dup.size
            }
        }

        currentResult = ScanResult(
            category: category,
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

    // MARK: - Shared helpers

    private func defaultScopes() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Pictures"),
        ]
    }

    private struct FileCandidate: Hashable {
        let url: URL
        let size: Int64
        let modDate: Date?
    }

    private func canonicalOrder(a: FileCandidate, b: FileCandidate) -> Bool {
        if let aDate = a.modDate, let bDate = b.modDate, aDate != bDate {
            return aDate < bDate
        }
        return a.url.path.count < b.url.path.count
    }

    private func enumerateCandidates(
        in root: URL,
        includeImagesOnly: Bool,
        into bySize: inout [Int64: [FileCandidate]]
    ) {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .fileSizeKey, .contentModificationDateKey,
                .isRegularFileKey, .isDirectoryKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        for case let url as URL in enumerator {
            if isCancelled { break }
            if url.pathComponents.contains(where: { component in
                Self.opaqueBundleSuffixes.contains(where: { component.hasSuffix($0) })
            }) { continue }

            guard
                let values = try? url.resourceValues(forKeys: [
                    .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
                ]),
                values.isRegularFile == true,
                let size = values.fileSize
            else { continue }

            let minSize: Int64 = includeImagesOnly ? 64 : Self.minFileSize
            guard Int64(size) >= minSize else { continue }

            if pathClassifier.classify(url) == .systemProtected { continue }

            if includeImagesOnly {
                let ext = url.pathExtension.lowercased()
                guard PerceptualHasher.imageExtensions.contains(ext) else { continue }
            }

            bySize[Int64(size), default: []].append(FileCandidate(
                url: url,
                size: Int64(size),
                modDate: values.contentModificationDate
            ))
        }
    }

    private static func hashFile(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let cont = autoreleasepool { () -> Bool in
                guard let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                    return false
                }
                hasher.update(data: chunk)
                return true
            }
            if !cont { break }
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
