import XCTest
@testable import DnDCategoriser

@MainActor
final class ShelfViewModelTests: XCTestCase {
    var tmp: URL!
    var existing: Folder!
    var missing: Folder!
    let files = [
        FileInfo(id: "f0", url: URL(fileURLWithPath: "/x/a.pdf"), name: "a", ext: "pdf", sizeBytes: 1),
        FileInfo(id: "f1", url: URL(fileURLWithPath: "/x/b.png"), name: "b", ext: "png", sizeBytes: 1),
        FileInfo(id: "f2", url: URL(fileURLWithPath: "/x/c.txt"), name: "c", ext: "txt", sizeBytes: 1),
    ]

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ShelfVM-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        existing = Folder(id: "docs", path: tmp, name: "Docs", description: "d")
        missing = Folder(id: "gone", path: tmp.appendingPathComponent("gone"), name: "Gone", description: "g")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    func testResetMarksMissingFolders() {
        let vm = ShelfViewModel()
        vm.reset(folders: [existing, missing], engine: .jev)
        XCTAssertEqual(vm.tiles.count, 2)
        XCTAssertFalse(vm.tiles[0].missing)
        XCTAssertEqual(vm.tiles[0].state, .idle)
        XCTAssertTrue(vm.tiles[1].missing)
        XCTAssertEqual(vm.tiles[1].state, .failed("Missing folder"))
        XCTAssertEqual(vm.activeFolders, [existing])
        XCTAssertEqual(vm.engineLabel, "Jev")
        vm.reset(folders: [], engine: .onDevice)
        XCTAssertEqual(vm.engineLabel, "On-device")
    }

    func testBeginSessionSetsPendingExceptMissing() {
        let vm = ShelfViewModel()
        vm.reset(folders: [existing, missing], engine: .jev)
        vm.beginSession()
        XCTAssertEqual(vm.tiles[0].state, .pending)
        XCTAssertEqual(vm.tiles[1].state, .failed("Missing folder"))
    }

    func testApplyGroupsFilesPerTile() {
        let vm = ShelfViewModel()
        let other = Folder(id: "shots", path: tmp, name: "Shots", description: "s")
        vm.reset(folders: [existing, other], engine: .jev)
        vm.beginSession()
        vm.apply(results: ["f0": "docs", "f2": "docs"], files: files)
        XCTAssertEqual(vm.tiles[0].state, .matches([files[0], files[2]]))
        XCTAssertEqual(vm.tiles[1].state, .empty)
        XCTAssertEqual(vm.matchedFiles(at: 0), [files[0], files[2]])
        XCTAssertNil(vm.matchedFiles(at: 1))
        XCTAssertNil(vm.matchedFiles(at: 5))
    }

    func testApplyTracksUnmatchedFilesAsExtraSlot() {
        let vm = ShelfViewModel()
        vm.reset(folders: [existing], engine: .jev)
        XCTAssertEqual(vm.slotCount, 1)
        XCTAssertNil(vm.unmatchedSlot)
        vm.beginSession()
        vm.apply(results: ["f1": "docs"], files: files)
        XCTAssertEqual(vm.unmatched, [files[0], files[2]])
        XCTAssertEqual(vm.slotCount, 2)
        XCTAssertEqual(vm.unmatchedSlot, 1)
        XCTAssertEqual(vm.flyout(forSlot: 0)?.title, "Docs")
        XCTAssertEqual(vm.flyout(forSlot: 0)?.files, [files[1]])
        XCTAssertEqual(vm.flyout(forSlot: 1)?.title, "No folder")
        XCTAssertEqual(vm.flyout(forSlot: 1)?.files, [files[0], files[2]])
        XCTAssertNil(vm.flyout(forSlot: 2))
    }

    func testResetClearsUnmatched() {
        let vm = ShelfViewModel()
        vm.reset(folders: [existing], engine: .jev)
        vm.apply(results: [:], files: files)
        XCTAssertEqual(vm.unmatched.count, 3)
        vm.reset(folders: [existing], engine: .jev)
        XCTAssertTrue(vm.unmatched.isEmpty)
        XCTAssertNil(vm.flyout(forSlot: 0)) // idle tile has no files
    }

    func testFailMarksAllNonMissing() {
        let vm = ShelfViewModel()
        vm.reset(folders: [existing, missing], engine: .jev)
        vm.fail("boom")
        XCTAssertEqual(vm.tiles[0].state, .failed("boom"))
        XCTAssertEqual(vm.tiles[1].state, .failed("Missing folder"))
    }
}
