import XCTest
import Foundation
import MPCore
@testable import MPScanners

// MARK: - Helpers

private func drainStream<T: Error>(_ stream: AsyncThrowingStream<ScanProgress, T>) async throws -> [ScanProgress] {
    var updates: [ScanProgress] = []
    for try await update in stream { updates.append(update) }
    return updates
}

private func makeTempDir(named label: String) throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("MPScannersTests-\(label)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}

private func writeFile(at url: URL, size bytes: Int = 512) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let data = Data(repeating: 0xAB, count: bytes)
    try data.write(to: url)
    // Back-date so SystemJunkScanner's 1-hour recency guard doesn't skip it
    let old = Date(timeIntervalSinceNow: -7200)
    try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
}

// MARK: - SystemJunkScanner Tests

final class SystemJunkScannerTests: XCTestCase {

    private var fixtureDir: URL!
    private var scanner: SystemJunkScanner!

    override func setUp() async throws {
        try await super.setUp()
        fixtureDir = try makeTempDir(named: "SystemJunk")
        scanner = SystemJunkScanner()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fixtureDir)
        try await super.tearDown()
    }

    func testScanYieldsCompletePhase() async throws {
        let stream = await scanner.scan()
        let updates = try await drainStream(stream)
        let phases = updates.map(\.phase)
        XCTAssertTrue(phases.contains(where: {
            if case .complete = $0 { return true }; return false
        }), "Stream must finish with .complete phase")
    }

    func testResultsNilBeforeScan() async {
        let result = await scanner.results()
        XCTAssertNil(result)
    }

    func testResultsAvailableAfterScan() async throws {
        let stream = await scanner.scan()
        _ = try await drainStream(stream)
        let result = await scanner.results()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, .systemJunk)
    }

    func testResetClearsResults() async throws {
        let stream = await scanner.scan()
        _ = try await drainStream(stream)
        await scanner.reset()
        let result = await scanner.results()
        XCTAssertNil(result)
    }

    func testCancelStopsEmitting() async throws {
        // Kick off scan then cancel immediately — should not deadlock
        let stream = await scanner.scan()
        await scanner.cancel()
        var count = 0
        for try await _ in stream { count += 1 }
        // We don't assert a specific count — just that it terminates
        XCTAssertGreaterThanOrEqual(count, 0)
    }

    func testScanItemsHaveValidPaths() async throws {
        let stream = await scanner.scan()
        _ = try await drainStream(stream)
        let items = await scanner.results()?.items ?? []
        for item in items {
            XCTAssertFalse(item.path.path.isEmpty, "ScanItem must have a non-empty path")
            XCTAssertGreaterThan(item.size, 0, "ScanItem must have a positive size")
        }
    }

    func testScanItemsNotInSIPPaths() async throws {
        let stream = await scanner.scan()
        _ = try await drainStream(stream)
        let items = await scanner.results()?.items ?? []
        let sipPrefixes = ["/System", "/usr/bin", "/usr/lib", "/usr/sbin", "/bin", "/sbin"]
        for item in items {
            let path = item.path.path
            for prefix in sipPrefixes {
                XCTAssertFalse(path.hasPrefix(prefix),
                    "Scanner must never return SIP-protected path: \(path)")
            }
        }
    }
}

// MARK: - TrashBinsScanner Tests

final class TrashBinsScannerTests: XCTestCase {

    private var fixtureTrash: URL!
    private var scanner: TrashBinsScanner!

    override func setUp() async throws {
        try await super.setUp()
        fixtureTrash = try makeTempDir(named: "TrashFixture")
        scanner = TrashBinsScanner()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fixtureTrash)
        try await super.tearDown()
    }

    func testScanYieldsCompletePhase() async throws {
        let stream = await scanner.scan()
        let updates = try await drainStream(stream)
        let phases = updates.map(\.phase)
        XCTAssertTrue(phases.contains(where: {
            if case .complete = $0 { return true }; return false
        }))
    }

    func testResultsAvailableAfterScan() async throws {
        let stream = await scanner.scan()
        _ = try await drainStream(stream)
        let result = await scanner.results()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, .trashBins)
    }

    func testResetClearsResults() async throws {
        let stream = await scanner.scan()
        _ = try await drainStream(stream)
        await scanner.reset()
        XCTAssertNil(await scanner.results())
    }

    func testScanFindsFilesInUserTrash() async throws {
        // Write a file directly into the real user Trash
        let trashURL = URL(fileURLWithPath: NSString(string: "~/.Trash").expandingTildeInPath)
        let sentinelName = "MPScannersTest-sentinel-\(UUID().uuidString).txt"
        let sentinelURL = trashURL.appendingPathComponent(sentinelName)

        do {
            try "test".write(to: sentinelURL, atomically: true, encoding: .utf8)
        } catch {
            throw XCTSkip("Cannot write to ~/.Trash — skipping: \(error)")
        }

        defer { try? FileManager.default.removeItem(at: sentinelURL) }

        let stream = await scanner.scan()
        _ = try await drainStream(stream)
        let items = await scanner.results()?.items ?? []
        let found = items.contains { $0.name == sentinelName }
        XCTAssertTrue(found, "Scanner must find a file that was placed directly in ~/.Trash")
    }

    func testTotalSizeMatchesItemSizes() async throws {
        let stream = await scanner.scan()
        _ = try await drainStream(stream)
        guard let result = await scanner.results() else { return }
        let summedSizes = result.items.reduce(0) { $0 + $1.size }
        XCTAssertEqual(result.totalSize, summedSizes,
            "result.totalSize must equal the sum of all item sizes")
    }

    func testCancelTerminatesStream() async throws {
        let stream = await scanner.scan()
        await scanner.cancel()
        var count = 0
        for try await _ in stream { count += 1 }
        XCTAssertGreaterThanOrEqual(count, 0)
    }
}

// MARK: - MailAttachmentsScanner Tests

final class MailAttachmentsScannerTests: XCTestCase {

    private var fixtureMailDir: URL!
    private var scanner: MailAttachmentsScanner!

    override func setUp() async throws {
        try await super.setUp()
        fixtureMailDir = try makeTempDir(named: "Mail")
        scanner = MailAttachmentsScanner()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fixtureMailDir)
        try await super.tearDown()
    }

    func testScanYieldsCompletePhase() async throws {
        let stream = await scanner.scan()
        let updates = try await drainStream(stream)
        XCTAssertTrue(updates.contains(where: {
            if case .complete = $0.phase { return true }; return false
        }))
    }

    func testResultsAvailableAfterScan() async throws {
        let stream = await scanner.scan()
        _ = try await drainStream(stream)
        let result = await scanner.results()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, .mailAttachments)
    }

    func testResetClearsResults() async throws {
        let stream = await scanner.scan()
        _ = try await drainStream(stream)
        await scanner.reset()
        XCTAssertNil(await scanner.results())
    }

    func testScanItemSizesAboveThreshold() async throws {
        let stream = await scanner.scan()
        _ = try await drainStream(stream)
        let items = await scanner.results()?.items ?? []
        for item in items {
            XCTAssertGreaterThan(item.size, 100_000,
                "Scanner must only surface attachments > 100 KB, got \(item.size) for \(item.name)")
        }
    }

    func testCancelTerminatesStream() async throws {
        let stream = await scanner.scan()
        await scanner.cancel()
        var count = 0
        for try await _ in stream { count += 1 }
        XCTAssertGreaterThanOrEqual(count, 0)
    }
}

// MARK: - TimeMachineScanner Tests

final class TimeMachineScannerTests: XCTestCase {

    private var scanner: TimeMachineScanner!

    override func setUp() async throws {
        try await super.setUp()
        scanner = TimeMachineScanner()
    }

    func testScanYieldsCompleteOrFailed() async throws {
        let stream = await scanner.scan()
        let updates = try await drainStream(stream)
        let phases = updates.map(\.phase)
        let terminated = phases.contains(where: {
            switch $0 {
            case .complete, .failed: return true
            default: return false
            }
        })
        XCTAssertTrue(terminated, "Stream must terminate with .complete or .failed")
    }

    func testResultsAvailableAfterCompletedScan() async throws {
        let stream = await scanner.scan()
        let updates = try await drainStream(stream)
        let didComplete = updates.contains(where: {
            if case .complete = $0.phase { return true }; return false
        })
        guard didComplete else {
            throw XCTSkip("tmutil not available or backup was running — skipping result assertion")
        }
        let result = await scanner.results()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, .timeMachine)
    }

    func testSnapshotNamesHaveTimeMachinePrefix() async throws {
        let stream = await scanner.scan()
        let updates = try await drainStream(stream)
        let didComplete = updates.contains(where: {
            if case .complete = $0.phase { return true }; return false
        })
        guard didComplete else {
            throw XCTSkip("tmutil not available or backup was running")
        }
        let items = await scanner.results()?.items ?? []
        for item in items {
            XCTAssertTrue(item.name.hasPrefix("com.apple.TimeMachine"),
                "Snapshot name must have com.apple.TimeMachine prefix, got: \(item.name)")
        }
    }

    func testResetClearsResults() async throws {
        let stream = await scanner.scan()
        _ = try await drainStream(stream)
        await scanner.reset()
        XCTAssertNil(await scanner.results())
    }

    func testCancelTerminatesStream() async throws {
        let stream = await scanner.scan()
        await scanner.cancel()
        var count = 0
        for try await _ in stream { count += 1 }
        XCTAssertGreaterThanOrEqual(count, 0)
    }
}

// MARK: - PathClassifier Tests

final class PathClassifierTests: XCTestCase {

    private let classifier = PathClassifier()
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    func testSIPPathsAreSystemProtected() {
        let sipPaths = [
            "/System/Library/CoreServices/Finder.app",
            "/usr/bin/swift",
            "/usr/lib/libSystem.B.dylib",
            "/bin/sh",
            "/sbin/launchd",
        ]
        for path in sipPaths {
            let result = classifier.classify(URL(fileURLWithPath: path))
            XCTAssertEqual(result, .systemProtected,
                "\(path) must be classified as systemProtected")
        }
    }

    func testUserCachesAreSafe() {
        let url = URL(fileURLWithPath: "\(home)/Library/Caches/com.example.app/something.cache")
        XCTAssertEqual(classifier.classify(url), .safe)
    }

    func testUserLogsAreSafe() {
        let url = URL(fileURLWithPath: "\(home)/Library/Logs/app.log")
        XCTAssertEqual(classifier.classify(url), .safe)
    }

    func testSystemCachesAreSafe() {
        let url = URL(fileURLWithPath: "/Library/Caches/com.apple.something/data")
        XCTAssertEqual(classifier.classify(url), .safe)
    }

    func testUserDocumentsAreUserData() {
        let url = URL(fileURLWithPath: "\(home)/Documents/important.pdf")
        XCTAssertEqual(classifier.classify(url), .userData)
    }

    func testDesktopIsUserData() {
        let url = URL(fileURLWithPath: "\(home)/Desktop/notes.txt")
        XCTAssertEqual(classifier.classify(url), .userData)
    }

    func testAppSupportIsCautionary() {
        let url = URL(fileURLWithPath: "\(home)/Library/Application Support/SomeApp/data.db")
        XCTAssertEqual(classifier.classify(url), .cautionary)
    }

    func testIsWritableBlocksSIPPaths() {
        let sipURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        XCTAssertFalse(classifier.isWritable(sipURL),
            "SIP-protected paths must not be writable")
    }

    func testIsWritableAllowsUserCaches() {
        let url = URL(fileURLWithPath: "\(home)/Library/Caches/test.cache")
        XCTAssertTrue(classifier.isWritable(url))
    }

    func testSymlinkEscapeDetection() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("MPClassifierSymlinkTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let target = tmp.appendingPathComponent("real.txt")
        try "data".write(to: target, atomically: true, encoding: .utf8)

        let link = tmp.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertTrue(classifier.containsSymlinkEscape(link),
            "Symlinks that resolve to a different path must be detected")
        XCTAssertFalse(classifier.containsSymlinkEscape(target),
            "A real file must not be flagged as a symlink escape")
    }
}
