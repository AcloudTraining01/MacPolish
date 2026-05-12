import Foundation
import Security
import MPCore

public actor ShredderEngine: MPCore.Scanner {
    public let category: ScanCategory = .shredder
    private var currentResult: ScanResult?
    private var queued: [URL] = []
    private var isCancelled = false

    public static let passes: Int = 3
    private static let chunkSize: UInt64 = 64 * 1024

    public init() {}

    public func enqueue(_ urls: [URL]) {
        for url in urls where !queued.contains(url) {
            queued.append(url)
        }
        rebuildResult()
    }

    public func dequeue(_ url: URL) {
        queued.removeAll { $0 == url }
        rebuildResult()
    }

    public func clearQueue() {
        queued.removeAll()
        rebuildResult()
    }

    public func queuedURLs() -> [URL] { queued }

    public func scan() -> AsyncThrowingStream<ScanProgress, Error> {
        isCancelled = false
        rebuildResult()
        return AsyncThrowingStream { continuation in
            continuation.yield(ScanProgress(category: category, phase: .preparing))
            continuation.yield(ScanProgress(
                category: category,
                phase: .complete,
                itemsFound: queued.count,
                bytesFound: currentResult?.totalSize ?? 0
            ))
            continuation.finish()
        }
    }

    public func results() -> ScanResult? { currentResult }
    public func cancel() { isCancelled = true }

    public func reset() {
        currentResult = nil
        queued.removeAll()
        isCancelled = false
    }

    public struct ShredOutcome: Sendable {
        public let url: URL
        public let success: Bool
        public let error: String?
    }

    public func shred() async -> [ShredOutcome] {
        isCancelled = false
        var outcomes: [ShredOutcome] = []
        let snapshot = queued

        for url in snapshot {
            if isCancelled { break }
            do {
                try Self.shredFile(at: url)
                outcomes.append(ShredOutcome(url: url, success: true, error: nil))
            } catch {
                outcomes.append(ShredOutcome(
                    url: url,
                    success: false,
                    error: error.localizedDescription
                ))
            }
        }

        let survivors = outcomes
            .filter { !$0.success }
            .map(\.url)
        queued = survivors
        rebuildResult()
        return outcomes
    }

    private func rebuildResult() {
        let items: [ScanItem] = queued.map { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return ScanItem(
                path: url,
                name: url.lastPathComponent,
                size: Int64(size),
                category: category,
                riskLevel: .dangerous
            )
        }
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        currentResult = ScanResult(
            category: category,
            items: items,
            totalSize: total,
            scanDuration: 0
        )
    }

    private static func shredFile(at url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            throw ShredError.notARegularFile(url)
        }

        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()

        for pass in 0..<passes {
            try handle.seek(toOffset: 0)
            try overwrite(handle: handle, length: size, pass: pass)
            try handle.synchronize()
        }

        try fm.removeItem(at: url)
    }

    private static func overwrite(handle: FileHandle, length: UInt64, pass: Int) throws {
        var remaining = length
        while remaining > 0 {
            let toWrite = Int(min(chunkSize, remaining))
            let data = chunkData(byteCount: toWrite, pass: pass)
            try handle.write(contentsOf: data)
            remaining -= UInt64(toWrite)
        }
    }

    private static func chunkData(byteCount: Int, pass: Int) -> Data {
        switch pass {
        case 0:
            return Data(repeating: 0x00, count: byteCount)
        case 1:
            return Data(repeating: 0xFF, count: byteCount)
        default:
            var bytes = [UInt8](repeating: 0, count: byteCount)
            _ = bytes.withUnsafeMutableBufferPointer { buffer in
                SecRandomCopyBytes(kSecRandomDefault, byteCount, buffer.baseAddress!)
            }
            return Data(bytes)
        }
    }

    public enum ShredError: Error, LocalizedError {
        case notARegularFile(URL)

        public var errorDescription: String? {
            switch self {
            case .notARegularFile(let url):
                return "Cannot shred (not a regular file): \(url.path)"
            }
        }
    }
}
