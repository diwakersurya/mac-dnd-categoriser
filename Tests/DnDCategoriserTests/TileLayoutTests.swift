import XCTest
@testable import DnDCategoriser

final class TileLayoutTests: XCTestCase {
    // Right edge (default): flyout 240 + gap 8 => shelf column at x=248, width 260; tiles 236x72; spacing 8; padding 12; margin 24.
    let right = TileLayout(edge: .right)
    let left = TileLayout(edge: .left)
    let top = TileLayout(edge: .top)
    let bottom = TileLayout(edge: .bottom)

    // MARK: right (vertical)

    func testRightPanelSizeAndShelfFrame() {
        XCTAssertEqual(right.panelSize(slotCount: 3), CGSize(width: 508, height: 256))
        XCTAssertEqual(right.panelSize(slotCount: 0), CGSize(width: 508, height: 24))
        XCTAssertEqual(right.shelfFrame(slotCount: 3), CGRect(x: 248, y: 0, width: 260, height: 256))
    }

    func testRightTileFrames() {
        XCTAssertEqual(right.frame(at: 0), CGRect(x: 260, y: 12, width: 236, height: 72))
        XCTAssertEqual(right.frame(at: 1), CGRect(x: 260, y: 92, width: 236, height: 72))
    }

    func testRightHitTesting() {
        XCTAssertEqual(right.tileIndex(at: CGPoint(x: 348, y: 130), tileCount: 3), 1)
        XCTAssertEqual(right.tileIndex(at: CGPoint(x: 348, y: 87), tileCount: 3), 0) // gap, nearer centre 48 than 128
        XCTAssertEqual(right.tileIndex(at: CGPoint(x: 348, y: 89), tileCount: 3), 1)
        XCTAssertEqual(right.tileIndex(at: CGPoint(x: 240, y: 48), tileCount: 3), 0) // within 24pt margin
        XCTAssertNil(right.tileIndex(at: CGPoint(x: 348, y: 500), tileCount: 1))
        XCTAssertNil(right.tileIndex(at: CGPoint(x: 220, y: 48), tileCount: 1))
        XCTAssertNil(right.tileIndex(at: CGPoint(x: 348, y: 48), tileCount: 0))
    }

    func testRightFlyout() {
        XCTAssertEqual(right.flyoutFrame(forSlot: 0, slotCount: 3, rowCount: 3), CGRect(x: 0, y: 12, width: 240, height: 102))
        XCTAssertEqual(right.flyoutFrame(forSlot: 2, slotCount: 3, rowCount: 10), CGRect(x: 0, y: 12, width: 240, height: 232))
        XCTAssertTrue(right.isOverFlyout(CGPoint(x: 100, y: 50), slotCount: 3))
        XCTAssertFalse(right.isOverFlyout(CGPoint(x: 300, y: 50), slotCount: 3))
    }

    // MARK: left (vertical, mirrored)

    func testLeftLayout() {
        XCTAssertEqual(left.shelfFrame(slotCount: 3), CGRect(x: 0, y: 0, width: 260, height: 256))
        XCTAssertEqual(left.frame(at: 0), CGRect(x: 12, y: 12, width: 236, height: 72))
        XCTAssertEqual(left.flyoutFrame(forSlot: 0, slotCount: 3, rowCount: 3), CGRect(x: 268, y: 12, width: 240, height: 102))
        XCTAssertEqual(left.tileIndex(at: CGPoint(x: 100, y: 130), tileCount: 3), 1)
        XCTAssertTrue(left.isOverFlyout(CGPoint(x: 400, y: 50), slotCount: 3))
        XCTAssertFalse(left.isOverFlyout(CGPoint(x: 100, y: 50), slotCount: 3))
    }

    // MARK: top (horizontal, flyout below)

    func testTopLayout() {
        // 3 tiles of 200 + 2 gaps of 8 + padding 24 = 640 wide; shelf 96 tall; flyout region 242 below a gap of 8.
        XCTAssertEqual(top.panelSize(slotCount: 3), CGSize(width: 640, height: 346))
        XCTAssertEqual(top.panelSize(slotCount: 1).width, 240) // never narrower than the flyout
        XCTAssertEqual(top.shelfFrame(slotCount: 3), CGRect(x: 0, y: 0, width: 640, height: 96))
        XCTAssertEqual(top.frame(at: 1), CGRect(x: 220, y: 12, width: 200, height: 72))
        XCTAssertEqual(top.tileIndex(at: CGPoint(x: 112, y: 48), tileCount: 3), 0)
        XCTAssertEqual(top.tileIndex(at: CGPoint(x: 500, y: 105), tileCount: 3), 2) // below shelf (bottom 84) but within 24pt margin
        XCTAssertNil(top.tileIndex(at: CGPoint(x: 500, y: 200), tileCount: 3))
        // flyout under tile 0 starts at its x; under tile 2 it is clamped so it stays inside the panel.
        XCTAssertEqual(top.flyoutFrame(forSlot: 0, slotCount: 3, rowCount: 3), CGRect(x: 12, y: 104, width: 240, height: 102))
        XCTAssertEqual(top.flyoutFrame(forSlot: 2, slotCount: 3, rowCount: 3).minX, 400)
        XCTAssertTrue(top.isOverFlyout(CGPoint(x: 100, y: 200), slotCount: 3))
        XCTAssertFalse(top.isOverFlyout(CGPoint(x: 100, y: 50), slotCount: 3))
    }

    // MARK: bottom (horizontal, flyout above)

    func testBottomLayout() {
        XCTAssertEqual(bottom.shelfFrame(slotCount: 3), CGRect(x: 0, y: 250, width: 640, height: 96))
        XCTAssertEqual(bottom.frame(at: 0), CGRect(x: 12, y: 262, width: 200, height: 72))
        // flyout sits directly above the shelf, bottom-aligned to the gap.
        XCTAssertEqual(bottom.flyoutFrame(forSlot: 0, slotCount: 3, rowCount: 3), CGRect(x: 12, y: 140, width: 240, height: 102))
        XCTAssertTrue(bottom.isOverFlyout(CGPoint(x: 100, y: 100), slotCount: 3))
        XCTAssertFalse(bottom.isOverFlyout(CGPoint(x: 100, y: 300), slotCount: 3))
    }

    func testSlideOffsetPointsOffscreen() {
        XCTAssertEqual(right.slideOffset, CGVector(dx: 24, dy: 0))
        XCTAssertEqual(left.slideOffset, CGVector(dx: -24, dy: 0))
        XCTAssertEqual(top.slideOffset, CGVector(dx: 0, dy: 24))
        XCTAssertEqual(bottom.slideOffset, CGVector(dx: 0, dy: -24))
    }
}
