import XCTest
@testable import DnDCategoriser

final class TileLayoutTests: XCTestCase {
    // flyout 240 + gap 8 => shelf column starts at x=248; shelf width 260; tile 72; spacing 8; padding 12; margin 24
    let layout = TileLayout()

    func testColumns() {
        XCTAssertEqual(layout.shelfX, 248)
        XCTAssertEqual(layout.totalWidth, 508)
    }

    func testPanelHeight() {
        XCTAssertEqual(layout.panelHeight(tileCount: 0), 24)
        XCTAssertEqual(layout.panelHeight(tileCount: 1), 96)
        XCTAssertEqual(layout.panelHeight(tileCount: 3), 256)
    }

    func testFrameAtIndexIsInsideShelfColumn() {
        XCTAssertEqual(layout.frame(at: 0), CGRect(x: 260, y: 12, width: 236, height: 72))
        XCTAssertEqual(layout.frame(at: 1), CGRect(x: 260, y: 92, width: 236, height: 72))
    }

    func testPointInsideTileHitsIt() {
        XCTAssertEqual(layout.tileIndex(at: CGPoint(x: 348, y: 130), tileCount: 3), 1)
    }

    func testPointInGapPicksNearestCentre() {
        // tile 0 centre y=48, tile 1 centre y=128
        XCTAssertEqual(layout.tileIndex(at: CGPoint(x: 348, y: 87), tileCount: 3), 0)
        XCTAssertEqual(layout.tileIndex(at: CGPoint(x: 348, y: 89), tileCount: 3), 1)
    }

    func testPointWithinMarginOutsideTileHits() {
        XCTAssertEqual(layout.tileIndex(at: CGPoint(x: 240, y: 48), tileCount: 3), 0)
    }

    func testPointBeyondMarginMisses() {
        XCTAssertNil(layout.tileIndex(at: CGPoint(x: 348, y: 500), tileCount: 1))
        XCTAssertNil(layout.tileIndex(at: CGPoint(x: 220, y: 48), tileCount: 1)) // flyout column
    }

    func testZeroTilesMisses() {
        XCTAssertNil(layout.tileIndex(at: CGPoint(x: 348, y: 48), tileCount: 0))
    }

    func testFlyoutAlignsToTileTop() {
        // header 30 + 3 rows * 20 + padding 12 = 102
        XCTAssertEqual(layout.flyoutFrame(forSlot: 0, slotCount: 3, rowCount: 3), CGRect(x: 0, y: 12, width: 240, height: 102))
    }

    func testFlyoutShiftsUpAndCapsWhenTooTall() {
        // 10 rows => 242 raw, capped to panel 256 - 24 = 232, so y clamps to padding
        XCTAssertEqual(layout.flyoutFrame(forSlot: 2, slotCount: 3, rowCount: 10), CGRect(x: 0, y: 12, width: 240, height: 232))
        // 12 rows uses at most flyoutMaxRows (10) for sizing
        XCTAssertEqual(layout.flyoutFrame(forSlot: 2, slotCount: 3, rowCount: 12).height, 232)
    }
}
