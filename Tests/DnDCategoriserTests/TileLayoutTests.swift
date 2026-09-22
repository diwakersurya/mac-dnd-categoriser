import XCTest
@testable import DnDCategoriser

final class TileLayoutTests: XCTestCase {
    let layout = TileLayout() // width 260, tile 96, spacing 8, padding 12, margin 24

    func testPanelHeight() {
        XCTAssertEqual(layout.panelHeight(tileCount: 0), 24)
        XCTAssertEqual(layout.panelHeight(tileCount: 1), 120)
        XCTAssertEqual(layout.panelHeight(tileCount: 3), 328)
    }

    func testFrameAtIndex() {
        XCTAssertEqual(layout.frame(at: 0), CGRect(x: 12, y: 12, width: 236, height: 96))
        XCTAssertEqual(layout.frame(at: 1), CGRect(x: 12, y: 116, width: 236, height: 96))
    }

    func testPointInsideTileHitsIt() {
        XCTAssertEqual(layout.tileIndex(at: CGPoint(x: 100, y: 130), tileCount: 3), 1)
    }

    func testPointInGapPicksNearestCentre() {
        // tile 0 centre y=60, tile 1 centre y=164. y=110 → 50 vs 54 → tile 0; y=114 → 54 vs 50 → tile 1.
        XCTAssertEqual(layout.tileIndex(at: CGPoint(x: 100, y: 110), tileCount: 3), 0)
        XCTAssertEqual(layout.tileIndex(at: CGPoint(x: 100, y: 114), tileCount: 3), 1)
    }

    func testPointWithinMarginOutsideTileHits() {
        // 20pt left of tile 0's left edge (x=12) is x=-8; within 24pt margin.
        XCTAssertEqual(layout.tileIndex(at: CGPoint(x: -8, y: 60), tileCount: 3), 0)
    }

    func testPointBeyondMarginMisses() {
        XCTAssertNil(layout.tileIndex(at: CGPoint(x: 100, y: 500), tileCount: 1))
        XCTAssertNil(layout.tileIndex(at: CGPoint(x: -40, y: 60), tileCount: 1))
    }

    func testZeroTilesMisses() {
        XCTAssertNil(layout.tileIndex(at: CGPoint(x: 100, y: 60), tileCount: 0))
    }
}
