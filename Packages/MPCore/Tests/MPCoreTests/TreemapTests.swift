import XCTest
import CoreGraphics
@testable import MPCore

final class TreemapTests: XCTestCase {

    func testEmptyInputReturnsEmpty() {
        let result = Treemap.layout([], in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertTrue(result.isEmpty)
    }

    func testZeroRectReturnsEmpty() {
        let entries = [TreemapEntry(label: "A", size: 100)]
        let result = Treemap.layout(entries, in: .zero)
        XCTAssertTrue(result.isEmpty)
    }

    func testSingleEntryFillsRect() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let entries = [TreemapEntry(label: "Solo", size: 1000)]
        let tiles = Treemap.layout(entries, in: rect)
        XCTAssertEqual(tiles.count, 1)
        XCTAssertEqual(tiles[0].rect.width, 200, accuracy: 0.5)
        XCTAssertEqual(tiles[0].rect.height, 100, accuracy: 0.5)
        XCTAssertEqual(tiles[0].label, "Solo")
        XCTAssertEqual(tiles[0].size, 1000)
    }

    func testAreaIsConserved() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 300)
        let entries = [
            TreemapEntry(label: "A", size: 600),
            TreemapEntry(label: "B", size: 300),
            TreemapEntry(label: "C", size: 100),
            TreemapEntry(label: "D", size: 50),
        ]
        let tiles = Treemap.layout(entries, in: rect)
        let totalArea = tiles.reduce(0.0) { $0 + Double($1.rect.width) * Double($1.rect.height) }
        let rectArea = Double(rect.width) * Double(rect.height)
        XCTAssertEqual(totalArea, rectArea, accuracy: rectArea * 0.001)
    }

    func testTileAreasProportionalToSizes() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 300)
        let entries = [
            TreemapEntry(label: "Big", size: 800),
            TreemapEntry(label: "Small", size: 200),
        ]
        let tiles = Treemap.layout(entries, in: rect)
        let big = tiles.first { $0.label == "Big" }!
        let small = tiles.first { $0.label == "Small" }!
        let bigArea = Double(big.rect.width) * Double(big.rect.height)
        let smallArea = Double(small.rect.width) * Double(small.rect.height)
        XCTAssertEqual(bigArea / smallArea, 4.0, accuracy: 0.05)
    }

    func testAllTilesContainedInRect() {
        let rect = CGRect(x: 10, y: 20, width: 200, height: 150)
        let entries = (1...10).map { TreemapEntry(label: "E\($0)", size: Int64($0 * 100)) }
        let tiles = Treemap.layout(entries, in: rect)
        for tile in tiles {
            XCTAssertGreaterThanOrEqual(tile.rect.minX, rect.minX - 0.5)
            XCTAssertGreaterThanOrEqual(tile.rect.minY, rect.minY - 0.5)
            XCTAssertLessThanOrEqual(tile.rect.maxX, rect.maxX + 0.5)
            XCTAssertLessThanOrEqual(tile.rect.maxY, rect.maxY + 0.5)
        }
    }

    func testZeroSizedEntriesAreSkipped() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let entries = [
            TreemapEntry(label: "Real", size: 500),
            TreemapEntry(label: "Empty", size: 0),
            TreemapEntry(label: "Negative", size: -10),
        ]
        let tiles = Treemap.layout(entries, in: rect)
        XCTAssertEqual(tiles.count, 1)
        XCTAssertEqual(tiles[0].label, "Real")
    }
}
