import XCTest
import Foundation
import CoreGraphics
import ImageIO
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
        let result = await scanner.results()
        XCTAssertNil(result)
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
        let result = await scanner.results()
        XCTAssertNil(result)
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
        let result = await scanner.results()
        XCTAssertNil(result)
    }

    func testCancelTerminatesStream() async throws {
        let stream = await scanner.scan()
        await scanner.cancel()
        var count = 0
        for try await _ in stream { count += 1 }
        XCTAssertGreaterThanOrEqual(count, 0)
    }
}

// MARK: - LargeOldFilesScanner Tests

final class LargeOldFilesScannerTests: XCTestCase {

    private var scanner: LargeOldFilesScanner!

    override func setUp() async throws {
        try await super.setUp()
        scanner = LargeOldFilesScanner()
    }

    func testScanYieldsCompletePhase() async throws {
        let stream = await scanner.scan()
        let updates = try await drainStream(stream)
        let phases = updates.map(\.phase)
        XCTAssertTrue(phases.contains(where: {
            if case .complete = $0 { return true }; return false
        }), "Stream must finish with .complete phase")
    }

    func testResultsAvailableAfterScan() async throws {
        let stream = await scanner.scan()
        _ = try await drainStream(stream)
        let result = await scanner.results()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, .largeOldFiles)
    }

    func testResetClearsResults() async throws {
        let stream = await scanner.scan()
        _ = try await drainStream(stream)
        await scanner.reset()
        let result = await scanner.results()
        XCTAssertNil(result)
    }

    func testItemsMeetSizeAndAgeThresholds() async throws {
        let stream = await scanner.scan()
        _ = try await drainStream(stream)
        let items = await scanner.results()?.items ?? []
        let cutoff = Date(timeIntervalSinceNow: -LargeOldFilesScanner.ageThresholdSeconds)
        for item in items {
            XCTAssertGreaterThan(item.size, LargeOldFilesScanner.sizeThreshold,
                "Item must be larger than threshold: \(item.path.path) (\(item.size))")
            if let modDate = item.lastModified {
                XCTAssertLessThan(modDate, cutoff,
                    "Item must be older than threshold: \(item.path.path) (\(modDate))")
            }
        }
    }

    func testItemsSkipBundles() async throws {
        let stream = await scanner.scan()
        _ = try await drainStream(stream)
        let items = await scanner.results()?.items ?? []
        let bundleSuffixes = [".app", ".photoslibrary", ".sparsebundle", ".framework", ".bundle"]
        for item in items {
            for component in item.path.pathComponents {
                for suffix in bundleSuffixes {
                    XCTAssertFalse(component.hasSuffix(suffix),
                        "Scanner must not surface paths inside \(suffix) bundles: \(item.path.path)")
                }
            }
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

// MARK: - UninstallerScanner Tests

final class UninstallerScannerTests: XCTestCase {

    private var fixtureRoot: URL!
    private var scanner: UninstallerScanner!

    override func setUp() async throws {
        try await super.setUp()
        fixtureRoot = try makeTempDir(named: "Uninstaller")
        scanner = UninstallerScanner()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fixtureRoot)
        try await super.tearDown()
    }

    private func makeFakeApp(name: String, bundleID: String, displayName: String? = nil) throws -> URL {
        let appURL = fixtureRoot.appendingPathComponent("\(name).app")
        let contents = appURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
        ]
        if let displayName { plist["CFBundleDisplayName"] = displayName }
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return appURL
    }

    func testDiscoversAppWithBundleID() async throws {
        _ = try makeFakeApp(name: "Sample", bundleID: "com.example.sample", displayName: "Sample App")

        let stream = await scanner.scan(scopes: [fixtureRoot])
        _ = try await drainStream(stream)
        let list = await scanner.uninstallableList()

        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.bundleID, "com.example.sample")
        XCTAssertEqual(list.first?.displayName, "Sample App")
    }

    func testFallsBackToBundleNameWhenDisplayNameMissing() async throws {
        _ = try makeFakeApp(name: "NamedOnly", bundleID: "com.example.namedonly")

        let stream = await scanner.scan(scopes: [fixtureRoot])
        _ = try await drainStream(stream)
        let list = await scanner.uninstallableList()
        XCTAssertEqual(list.first?.displayName, "NamedOnly")
    }

    func testSkipsBundlesWithoutInfoPlist() async throws {
        let broken = fixtureRoot.appendingPathComponent("Broken.app")
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)

        let stream = await scanner.scan(scopes: [fixtureRoot])
        _ = try await drainStream(stream)
        let list = await scanner.uninstallableList()
        XCTAssertTrue(list.isEmpty)
    }

    func testIgnoresNonAppEntries() async throws {
        let textFile = fixtureRoot.appendingPathComponent("Notes.txt")
        try "hello".write(to: textFile, atomically: true, encoding: .utf8)
        _ = try makeFakeApp(name: "Real", bundleID: "com.example.real")

        let stream = await scanner.scan(scopes: [fixtureRoot])
        _ = try await drainStream(stream)
        let list = await scanner.uninstallableList()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.bundleID, "com.example.real")
    }

    func testResetClearsList() async throws {
        _ = try makeFakeApp(name: "Sample", bundleID: "com.example.sample")
        let stream = await scanner.scan(scopes: [fixtureRoot])
        _ = try await drainStream(stream)
        await scanner.reset()
        let list = await scanner.uninstallableList()
        let result = await scanner.results()
        XCTAssertTrue(list.isEmpty)
        XCTAssertNil(result)
    }

    func testCancelTerminatesStream() async throws {
        let stream = await scanner.scan(scopes: [fixtureRoot])
        await scanner.cancel()
        var count = 0
        for try await _ in stream { count += 1 }
        XCTAssertGreaterThanOrEqual(count, 0)
    }
}

// MARK: - ShredderEngine Tests

final class ShredderEngineTests: XCTestCase {

    private var fixtureRoot: URL!
    private var engine: ShredderEngine!

    override func setUp() async throws {
        try await super.setUp()
        fixtureRoot = try makeTempDir(named: "Shredder")
        engine = ShredderEngine()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fixtureRoot)
        try await super.tearDown()
    }

    func testEnqueueDequeue() async throws {
        let url = fixtureRoot.appendingPathComponent("a.bin")
        try "hi".write(to: url, atomically: true, encoding: .utf8)

        await engine.enqueue([url])
        var q = await engine.queuedURLs()
        XCTAssertEqual(q, [url])

        await engine.dequeue(url)
        q = await engine.queuedURLs()
        XCTAssertTrue(q.isEmpty)
    }

    func testEnqueueDeduplicates() async throws {
        let url = fixtureRoot.appendingPathComponent("a.bin")
        try Data([0x01, 0x02]).write(to: url)
        await engine.enqueue([url, url, url])
        let q = await engine.queuedURLs()
        XCTAssertEqual(q.count, 1)
    }

    func testShredRemovesFile() async throws {
        let url = fixtureRoot.appendingPathComponent("doomed.bin")
        let payload = Data(repeating: 0xAB, count: 4096)
        try payload.write(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        await engine.enqueue([url])
        let outcomes = await engine.shred()
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertTrue(outcomes[0].success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        let queued = await engine.queuedURLs()
        XCTAssertTrue(queued.isEmpty, "Successful shreds must be removed from queue")
    }

    func testShredFailsGracefullyForMissingFile() async throws {
        let url = fixtureRoot.appendingPathComponent("not-there.bin")
        await engine.enqueue([url])
        let outcomes = await engine.shred()
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertFalse(outcomes[0].success)
        XCTAssertNotNil(outcomes[0].error)

        let queued = await engine.queuedURLs()
        XCTAssertEqual(queued, [url], "Failed shreds remain in queue for retry")
    }

    func testScanReportsQueuedItems() async throws {
        let urlA = fixtureRoot.appendingPathComponent("a.bin")
        let urlB = fixtureRoot.appendingPathComponent("b.bin")
        try Data(repeating: 0x01, count: 1000).write(to: urlA)
        try Data(repeating: 0x02, count: 2000).write(to: urlB)
        await engine.enqueue([urlA, urlB])
        let stream = await engine.scan()
        _ = try await drainStream(stream)
        let result = await engine.results()
        XCTAssertEqual(result?.items.count, 2)
        XCTAssertEqual(result?.totalSize, 3000)
    }

    func testResetClearsQueue() async throws {
        let url = fixtureRoot.appendingPathComponent("a.bin")
        try Data([0x00]).write(to: url)
        await engine.enqueue([url])
        await engine.reset()
        let queued = await engine.queuedURLs()
        XCTAssertTrue(queued.isEmpty)
    }
}

// MARK: - DuplicateScanner Tests

final class DuplicateScannerTests: XCTestCase {

    private var fixtureRoot: URL!
    private var scanner: DuplicateScanner!

    override func setUp() async throws {
        try await super.setUp()
        fixtureRoot = try makeTempDir(named: "DuplicateFinder")
        scanner = DuplicateScanner()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fixtureRoot)
        try await super.tearDown()
    }

    private func write(_ url: URL, bytes: Data, modDate: Date? = nil) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try bytes.write(to: url)
        if let modDate {
            try FileManager.default.setAttributes(
                [.modificationDate: modDate], ofItemAtPath: url.path
            )
        }
    }

    func testFindsTwoByteIdenticalFiles() async throws {
        let payload = Data(repeating: 0xCD, count: 8192)
        let a = fixtureRoot.appendingPathComponent("a/file.bin")
        let b = fixtureRoot.appendingPathComponent("b/file.bin")
        let unique = fixtureRoot.appendingPathComponent("c/other.bin")
        try write(a, bytes: payload, modDate: Date(timeIntervalSinceNow: -10000))
        try write(b, bytes: payload, modDate: Date(timeIntervalSinceNow: -1000))
        try write(unique, bytes: Data(repeating: 0x77, count: 8192))

        let stream = await scanner.scan(scopes: [fixtureRoot])
        _ = try await drainStream(stream)
        let items = await scanner.results()?.items ?? []
        XCTAssertEqual(items.count, 1, "Should surface exactly the duplicate (the canonical is kept)")
        XCTAssertTrue(items.first?.path.path.hasSuffix("b/file.bin") ?? false,
            "The newer copy should be marked as the duplicate, got \(items.first?.path.path ?? "nil")")
        XCTAssertEqual(items.first?.explanation?.contains("a/file.bin"), true,
            "Explanation should point at the canonical copy")
    }

    func testDoesNotFlagDifferentSizes() async throws {
        let a = fixtureRoot.appendingPathComponent("a.bin")
        let b = fixtureRoot.appendingPathComponent("b.bin")
        try write(a, bytes: Data(repeating: 0xAA, count: 8192))
        try write(b, bytes: Data(repeating: 0xAA, count: 16384))

        let stream = await scanner.scan(scopes: [fixtureRoot])
        _ = try await drainStream(stream)
        let items = await scanner.results()?.items ?? []
        XCTAssertEqual(items.count, 0)
    }

    func testDoesNotFlagSameSizeButDifferentContent() async throws {
        let a = fixtureRoot.appendingPathComponent("a.bin")
        let b = fixtureRoot.appendingPathComponent("b.bin")
        try write(a, bytes: Data(repeating: 0x01, count: 8192))
        try write(b, bytes: Data(repeating: 0x02, count: 8192))

        let stream = await scanner.scan(scopes: [fixtureRoot])
        _ = try await drainStream(stream)
        let items = await scanner.results()?.items ?? []
        XCTAssertEqual(items.count, 0)
    }

    func testSkipsFilesBelowMinSize() async throws {
        let payload = Data(repeating: 0x33, count: 256)
        let a = fixtureRoot.appendingPathComponent("tiny-a.bin")
        let b = fixtureRoot.appendingPathComponent("tiny-b.bin")
        try write(a, bytes: payload)
        try write(b, bytes: payload)

        let stream = await scanner.scan(scopes: [fixtureRoot])
        _ = try await drainStream(stream)
        let items = await scanner.results()?.items ?? []
        XCTAssertEqual(items.count, 0, "Files below \(DuplicateScanner.minFileSize) bytes must not be flagged")
    }

    func testTripletProducesTwoDuplicates() async throws {
        let payload = Data(repeating: 0xBE, count: 8192)
        let oldest = fixtureRoot.appendingPathComponent("oldest.bin")
        let middle = fixtureRoot.appendingPathComponent("middle.bin")
        let newest = fixtureRoot.appendingPathComponent("newest.bin")
        try write(oldest, bytes: payload, modDate: Date(timeIntervalSinceNow: -10000))
        try write(middle, bytes: payload, modDate: Date(timeIntervalSinceNow: -5000))
        try write(newest, bytes: payload, modDate: Date(timeIntervalSinceNow: -100))

        let stream = await scanner.scan(scopes: [fixtureRoot])
        _ = try await drainStream(stream)
        let items = await scanner.results()?.items ?? []
        XCTAssertEqual(items.count, 2)
        let paths = items.map(\.path.path).sorted()
        XCTAssertTrue(paths.contains(where: { $0.hasSuffix("middle.bin") }))
        XCTAssertTrue(paths.contains(where: { $0.hasSuffix("newest.bin") }))
    }

    func testResetClearsResults() async throws {
        let payload = Data(repeating: 0x55, count: 8192)
        try write(fixtureRoot.appendingPathComponent("a.bin"), bytes: payload)
        try write(fixtureRoot.appendingPathComponent("b.bin"), bytes: payload)
        let stream = await scanner.scan(scopes: [fixtureRoot])
        _ = try await drainStream(stream)
        await scanner.reset()
        let result = await scanner.results()
        XCTAssertNil(result)
    }

    func testCancelTerminatesStream() async throws {
        let stream = await scanner.scan(scopes: [fixtureRoot])
        await scanner.cancel()
        var count = 0
        for try await _ in stream { count += 1 }
        XCTAssertGreaterThanOrEqual(count, 0)
    }
}

// MARK: - Perceptual Duplicate Tests

final class PerceptualDuplicateTests: XCTestCase {

    private var fixtureRoot: URL!
    private var scanner: DuplicateScanner!

    override func setUp() async throws {
        try await super.setUp()
        fixtureRoot = try makeTempDir(named: "PerceptualDup")
        scanner = DuplicateScanner()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fixtureRoot)
        try await super.tearDown()
    }

    private func writeSolidPNG(at url: URL, color: UInt8) throws {
        let width = 64
        let height = 64
        let bytesPerRow = width
        var pixels = [UInt8](repeating: color, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = pixels.withUnsafeMutableBytes({ buffer -> CGContext? in
            guard let base = buffer.baseAddress else { return nil }
            return CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        }), let cgImage = context.makeImage() else {
            throw NSError(domain: "test", code: -1)
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw NSError(domain: "test", code: -2)
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "test", code: -3)
        }
    }

    private func writeGradientPNG(at url: URL) throws {
        let width = 64
        let height = 64
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = UInt8((x * 255) / max(width - 1, 1))
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = pixels.withUnsafeMutableBytes({ buffer -> CGContext? in
            guard let base = buffer.baseAddress else { return nil }
            return CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        }), let cgImage = context.makeImage() else {
            throw NSError(domain: "test", code: -1)
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw NSError(domain: "test", code: -2)
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "test", code: -3)
        }
    }

    func testPerceptualHashIsDeterministic() throws {
        let url = fixtureRoot.appendingPathComponent("solid.png")
        try writeSolidPNG(at: url, color: 128)
        let first = PerceptualHasher.hash(url: url)
        let second = PerceptualHasher.hash(url: url)
        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
    }

    func testDifferentImagesHaveDifferentHashes() throws {
        let solid = fixtureRoot.appendingPathComponent("solid.png")
        let gradient = fixtureRoot.appendingPathComponent("gradient.png")
        try writeSolidPNG(at: solid, color: 128)
        try writeGradientPNG(at: gradient)
        let h1 = PerceptualHasher.hash(url: solid)!
        let h2 = PerceptualHasher.hash(url: gradient)!
        let distance = PerceptualHasher.hammingDistance(h1, h2)
        XCTAssertGreaterThan(distance, DuplicateScanner.perceptualHammingThreshold,
            "Solid vs gradient should be far in Hamming space (got \(distance))")
    }

    func testPerceptualScanGroupsSimilarImages() async throws {
        let copyA = fixtureRoot.appendingPathComponent("a/photo.png")
        let copyB = fixtureRoot.appendingPathComponent("b/photo-renamed.png")
        let unrelated = fixtureRoot.appendingPathComponent("c/gradient.png")
        try writeSolidPNG(at: copyA, color: 100)
        try writeSolidPNG(at: copyB, color: 100)
        try writeGradientPNG(at: unrelated)

        let stream = await scanner.scan(scopes: [fixtureRoot], mode: .perceptual)
        _ = try await drainStream(stream)
        let items = await scanner.results()?.items ?? []
        XCTAssertEqual(items.count, 1,
            "Two visually identical images should produce exactly one duplicate marker")
    }

    func testPerceptualScanSkipsNonImages() async throws {
        let textFile = fixtureRoot.appendingPathComponent("note.txt")
        try Data(repeating: 0x33, count: 8192).write(to: textFile)
        let stream = await scanner.scan(scopes: [fixtureRoot], mode: .perceptual)
        _ = try await drainStream(stream)
        let items = await scanner.results()?.items ?? []
        XCTAssertTrue(items.isEmpty)
    }
}

// MARK: - SpaceLensScanner Tests

final class SpaceLensScannerTests: XCTestCase {

    private var fixtureRoot: URL!
    private var scanner: SpaceLensScanner!

    override func setUp() async throws {
        try await super.setUp()
        fixtureRoot = try makeTempDir(named: "SpaceLens")
        scanner = SpaceLensScanner()
        // Build a tiny tree with known shapes
        let subA = fixtureRoot.appendingPathComponent("FolderA")
        let subB = fixtureRoot.appendingPathComponent("FolderB")
        try FileManager.default.createDirectory(at: subA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subB, withIntermediateDirectories: true)
        try writeFile(at: subA.appendingPathComponent("big.bin"), size: 2_500_000)
        try writeFile(at: subA.appendingPathComponent("small.bin"), size: 50_000)
        try writeFile(at: subB.appendingPathComponent("medium.bin"), size: 1_500_000)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fixtureRoot)
        try await super.tearDown()
    }

    func testScanYieldsCompletePhase() async throws {
        let stream = await scanner.scan(at: fixtureRoot)
        let updates = try await drainStream(stream)
        XCTAssertTrue(updates.contains(where: {
            if case .complete = $0.phase { return true }; return false
        }))
    }

    func testTreeAvailableAfterScan() async throws {
        let stream = await scanner.scan(at: fixtureRoot)
        _ = try await drainStream(stream)
        let tree = await scanner.tree()
        XCTAssertNotNil(tree)
        XCTAssertTrue(tree?.isDirectory ?? false)
    }

    func testRootSizeMatchesSumOfChildren() async throws {
        let stream = await scanner.scan(at: fixtureRoot)
        _ = try await drainStream(stream)
        guard let tree = await scanner.tree() else {
            XCTFail("Tree missing")
            return
        }
        let childSum = tree.children.reduce(Int64(0)) { $0 + $1.size }
        XCTAssertEqual(tree.size, childSum)
    }

    func testSurfacesLargeChildren() async throws {
        let stream = await scanner.scan(at: fixtureRoot)
        _ = try await drainStream(stream)
        let tree = await scanner.tree()
        let names = Set((tree?.children ?? []).map(\.name))
        XCTAssertTrue(names.contains("FolderA"))
        XCTAssertTrue(names.contains("FolderB"))
    }

    func testSIPPathsNotInTree() async throws {
        let stream = await scanner.scan(at: fixtureRoot)
        _ = try await drainStream(stream)
        guard let tree = await scanner.tree() else { return }
        let sipPrefixes = ["/System", "/usr/bin", "/usr/lib", "/usr/sbin", "/bin", "/sbin"]
        walkTree(tree) { node in
            for prefix in sipPrefixes {
                XCTAssertFalse(node.url.path.hasPrefix(prefix),
                    "Tree must not contain SIP-protected path: \(node.url.path)")
            }
        }
    }

    func testResetClearsTree() async throws {
        let stream = await scanner.scan(at: fixtureRoot)
        _ = try await drainStream(stream)
        await scanner.reset()
        let tree = await scanner.tree()
        let result = await scanner.results()
        XCTAssertNil(tree)
        XCTAssertNil(result)
    }

    func testCancelTerminatesStream() async throws {
        let stream = await scanner.scan(at: fixtureRoot)
        await scanner.cancel()
        var count = 0
        for try await _ in stream { count += 1 }
        XCTAssertGreaterThanOrEqual(count, 0)
    }

    private func walkTree(_ node: DirectoryNode, _ visit: (DirectoryNode) -> Void) {
        visit(node)
        for child in node.children {
            walkTree(child, visit)
        }
    }
}

// MARK: - M4 scanner sanity tests

final class M4ScannerTests: XCTestCase {

    private var fixtureRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        fixtureRoot = try makeTempDir(named: "M4")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fixtureRoot)
        try await super.tearDown()
    }

    func testExtensionsScannerFindsPluginByExtension() async throws {
        let dir = fixtureRoot.appendingPathComponent("Spotlight")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plugin = dir.appendingPathComponent("Sample.mdimporter")
        try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
        try Data([0, 0]).write(to: plugin.appendingPathComponent("contents"))

        let scanner = ExtensionsScanner()
        let stream = await scanner.scan(locations: [(dir, "Spotlight (test)", "mdimporter")])
        _ = try await drainStream(stream)
        let items = await scanner.results()?.items ?? []
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "Sample.mdimporter")
        XCTAssertEqual(items.first?.explanation, "Spotlight (test)")
    }

    func testOptimizationScannerReadsLabelFromPlist() async throws {
        let dir = fixtureRoot.appendingPathComponent("LaunchAgents")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plistURL = dir.appendingPathComponent("com.example.sample.plist")
        let plist: [String: Any] = [
            "Label": "com.example.sample",
            "Program": "/usr/local/bin/sample",
            "RunAtLoad": true,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)

        let scanner = OptimizationScanner()
        let stream = await scanner.scan(locations: [(dir, "Test launch agent")])
        _ = try await drainStream(stream)
        let items = await scanner.results()?.items ?? []
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "com.example.sample")
        XCTAssertTrue(items.first?.explanation?.contains("/usr/local/bin/sample") ?? false)
        XCTAssertTrue(items.first?.explanation?.contains("at login") ?? false)
    }

    func testUpdaterScannerReadsAppVersion() async throws {
        let appURL = fixtureRoot.appendingPathComponent("Test.app")
        let contents = appURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.test",
            "CFBundleName": "Test",
            "CFBundleShortVersionString": "2.4.1",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))

        let scanner = UpdaterScanner()
        let stream = await scanner.scan(scopes: [fixtureRoot])
        _ = try await drainStream(stream)
        let items = await scanner.results()?.items ?? []
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "Test")
        XCTAssertTrue(items.first?.explanation?.contains("v2.4.1") ?? false)
    }

    func testSystemMonitorSnapshotReturnsValidNumbers() async throws {
        let collector = SystemMonitorCollector()
        let snap = await collector.sampleOnce()
        XCTAssertGreaterThanOrEqual(snap.memoryTotalBytes, 1)
        XCTAssertGreaterThanOrEqual(snap.memoryUsedBytes, 0)
        XCTAssertLessThanOrEqual(snap.memoryUsedBytes, snap.memoryTotalBytes)
        XCTAssertGreaterThanOrEqual(snap.cpuBusyPercent, 0)
        XCTAssertLessThanOrEqual(snap.cpuBusyPercent + snap.cpuIdlePercent, 101)
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
