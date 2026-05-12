import MPCore

public actor PhotoLibraryScanner: MPCore.Scanner {
    public let category: ScanCategory = .photoLibrary
    private var currentResult: ScanResult?
    private var isCancelled = false

    public init() {}

    public func scan() -> AsyncThrowingStream<ScanProgress, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(ScanProgress(category: category, phase: .preparing))
            continuation.yield(ScanProgress(category: category, phase: .complete))
            continuation.finish()
        }
    }

    public func results() -> ScanResult? { currentResult }
    public func cancel() { isCancelled = true }
    public func reset() { currentResult = nil; isCancelled = false }
}
