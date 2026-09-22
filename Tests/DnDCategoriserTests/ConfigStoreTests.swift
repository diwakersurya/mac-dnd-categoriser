import XCTest
@testable import DnDCategoriser

final class ConfigStoreTests: XCTestCase {
    var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigStoreTests-\(UUID().uuidString)/nested/config.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent())
    }

    func testMissingFileGivesDefaults() {
        let store = ConfigStore(url: url)
        XCTAssertEqual(store.config, Config())
    }

    func testAddFolderPersistsAndReloads() {
        let store = ConfigStore(url: url)
        let f = store.addFolder(path: URL(fileURLWithPath: "/Users/me/Invoices"), description: "Bills")
        XCTAssertEqual(f.id, "invoices")
        XCTAssertEqual(f.name, "Invoices")
        store.config.engine = .onDevice

        let reloaded = ConfigStore(url: url)
        XCTAssertEqual(reloaded.config.folders, [f])
        XCTAssertEqual(reloaded.config.engine, .onDevice)
    }

    func testDuplicateNamesGetDistinctIds() {
        let store = ConfigStore(url: url)
        let a = store.addFolder(path: URL(fileURLWithPath: "/a/Docs"), description: "")
        let b = store.addFolder(path: URL(fileURLWithPath: "/b/Docs"), description: "")
        XCTAssertEqual(a.id, "docs")
        XCTAssertEqual(b.id, "docs_2")
    }

    func testRemoveFolder() {
        let store = ConfigStore(url: url)
        let a = store.addFolder(path: URL(fileURLWithPath: "/a/Docs"), description: "")
        store.removeFolder(id: a.id)
        XCTAssertTrue(store.config.folders.isEmpty)
        XCTAssertTrue(ConfigStore(url: url).config.folders.isEmpty)
    }

    func testDecodesConfigWrittenBeforeShowInDockExisted() throws {
        let json = #"{"engine":"onDevice","folders":[{"id":"a","name":"A","description":"","path":"file:///tmp/"}]}"#
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(c.engine, .onDevice)
        XCTAssertEqual(c.folders.count, 1)
        XCTAssertFalse(c.showInDock)
    }

    func testShowInDockRoundTrips() throws {
        var c = Config()
        c.showInDock = true
        let data = try JSONEncoder().encode(c)
        XCTAssertTrue(try JSONDecoder().decode(Config.self, from: data).showInDock)
    }

    func testCorruptFileGivesDefaults() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(ConfigStore(url: url).config, Config())
    }
}
