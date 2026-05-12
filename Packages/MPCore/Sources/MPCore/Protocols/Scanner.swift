import Foundation

public protocol Scanner: Actor {
    var category: ScanCategory { get }
    func scan() -> AsyncThrowingStream<ScanProgress, Error>
    func results() async -> ScanResult?
    func cancel() async
    func reset() async
}
