import Foundation
import XCTest
@testable import MPCore

final class MPCoreTests: XCTestCase {
    func testPathClassifierSIPProtection() {
        let classifier = PathClassifier()
        let systemPath = URL(fileURLWithPath: "/System/Library/Frameworks/AppKit.framework")
        XCTAssertEqual(classifier.classify(systemPath), .systemProtected)
        XCTAssertFalse(classifier.isWritable(systemPath))
    }

    func testPathClassifierSafeCaches() {
        let classifier = PathClassifier()
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let cachePath = homeDir.appendingPathComponent("Library/Caches/com.example.app")
        XCTAssertEqual(classifier.classify(cachePath), .safe)
        XCTAssertTrue(classifier.isWritable(cachePath))
    }

    func testPathClassifierUserData() {
        let classifier = PathClassifier()
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let docPath = homeDir.appendingPathComponent("Documents/important.txt")
        XCTAssertEqual(classifier.classify(docPath), .userData)
    }

    func testSizeFormatter() {
        XCTAssertFalse(SizeFormatter.format(1024).isEmpty)
        XCTAssertFalse(SizeFormatter.format(1_073_741_824).isEmpty)
    }

    func testProfileTypeCategories() {
        let dev = ProfileType.developer
        XCTAssertTrue(dev.prioritizedCategories.contains(.systemJunk))

        let casual = ProfileType.casual
        XCTAssertTrue(casual.prioritizedCategories.contains(.smartScan))
    }

    func testScanCategoryGroups() {
        XCTAssertEqual(ScanCategory.systemJunk.group, .cleanup)
        XCTAssertEqual(ScanCategory.spaceLens.group, .files)
        XCTAssertEqual(ScanCategory.uninstaller.group, .apps)
        XCTAssertEqual(ScanCategory.optimization.group, .speed)
        XCTAssertEqual(ScanCategory.malwareRemoval.group, .protection)
        XCTAssertEqual(ScanCategory.smartScan.group, .ai)
    }
}
