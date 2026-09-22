import XCTest
@testable import DnDCategoriser

final class FileMoverTests: XCTestCase {
    var root: URL!
    var src: URL!
    var dest: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("FileMoverTests-\(UUID().uuidString)")
        src = root.appendingPathComponent("src")
        dest = root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ name: String, in dir: URL, _ contents: String = "x") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testMovesFileIntoFolder() throws {
        let a = try write("a.txt", in: src)
        let result = FileMover.move([a], into: dest)
        XCTAssertEqual(result.moved[a], dest.appendingPathComponent("a.txt"))
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.txt").path))
    }

    func testCollisionAppendsCounterBeforeExtension() throws {
        _ = try write("a.txt", in: dest, "existing")
        _ = try write("a (2).txt", in: dest, "existing2")
        let a = try write("a.txt", in: src, "new")
        let result = FileMover.move([a], into: dest)
        XCTAssertEqual(result.moved[a]?.lastPathComponent, "a (3).txt")
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("a.txt"), encoding: .utf8), "existing")
    }

    func testCollisionWithoutExtension() throws {
        _ = try write("README", in: dest)
        let r = try write("README", in: src)
        let result = FileMover.move([r], into: dest)
        XCTAssertEqual(result.moved[r]?.lastPathComponent, "README (2)")
    }

    func testAfterEachReportsProgressPerFile() throws {
        let a = try write("a.txt", in: src)
        let b = try write("b.txt", in: src)
        let ghost = src.appendingPathComponent("ghost.txt")
        var seen: [(Int, Int)] = []
        _ = FileMover.move([a, ghost, b], into: dest) { done, total in seen.append((done, total)) }
        XCTAssertEqual(seen.map(\.0), [1, 2, 3])
        XCTAssertEqual(seen.map(\.1), [3, 3, 3])
    }

    func testMissingSourceIsReportedAndOthersStillMove() throws {
        let a = try write("a.txt", in: src)
        let ghost = src.appendingPathComponent("ghost.txt")
        let result = FileMover.move([ghost, a], into: dest)
        XCTAssertEqual(result.moved.count, 1)
        XCTAssertNotNil(result.failed[ghost])
    }
}
