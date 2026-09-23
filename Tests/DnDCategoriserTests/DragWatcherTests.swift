import XCTest
import AppKit
@testable import DnDCategoriser

final class DragWatcherTests: XCTestCase {
    func testFileURLsReadsOnlyFileURLs() {
        let pb = NSPasteboard(name: NSPasteboard.Name("DragWatcherTests-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        let a = NSURL(fileURLWithPath: "/tmp/a.txt")
        let b = NSURL(fileURLWithPath: "/tmp/b.pdf")
        XCTAssertTrue(pb.writeObjects([a, b]))
        XCTAssertEqual(DragWatcher.fileURLs(from: pb), [a as URL, b as URL])
    }

    func testFileURLsDropsFoldersKeepsFilesAndPackages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DragWatcherTests-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("Photos")
        let package = root.appendingPathComponent("Tool.app")
        let file = root.appendingPathComponent("note.txt")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: root) }

        let pb = NSPasteboard(name: NSPasteboard.Name("DragWatcherTests-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        XCTAssertTrue(pb.writeObjects([folder as NSURL, file as NSURL, package as NSURL]))
        XCTAssertEqual(DragWatcher.fileURLs(from: pb).map(\.lastPathComponent), ["note.txt", "Tool.app"])
    }

    func testFileURLsIgnoresPlainText() {
        let pb = NSPasteboard(name: NSPasteboard.Name("DragWatcherTests-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("hello", forType: .string)
        XCTAssertEqual(DragWatcher.fileURLs(from: pb), [])
    }

    func testFileURLsIgnoresWebURLs() {
        let pb = NSPasteboard(name: NSPasteboard.Name("DragWatcherTests-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        XCTAssertTrue(pb.writeObjects([NSURL(string: "https://example.com")!]))
        XCTAssertEqual(DragWatcher.fileURLs(from: pb), [])
    }
}
