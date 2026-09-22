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
