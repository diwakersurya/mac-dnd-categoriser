import XCTest
@testable import DnDCategoriser

final class SlugTests: XCTestCase {
    func testLowercasesAndReplacesNonAlphanumerics() {
        XCTAssertEqual(Slug.make(from: "Bug Screenshots!", existing: []), "bug_screenshots")
    }

    func testCollapsesRunsAndTrimsUnderscores() {
        XCTAssertEqual(Slug.make(from: "  --Invoices  2026-- ", existing: []), "invoices_2026")
    }

    func testEmptyFallsBackToFolder() {
        XCTAssertEqual(Slug.make(from: "###", existing: []), "folder")
    }

    func testReservedNoneIsRenamed() {
        XCTAssertEqual(Slug.make(from: "None", existing: []), "none_folder")
    }

    func testDeduplicatesWithNumericSuffix() {
        XCTAssertEqual(Slug.make(from: "Docs", existing: ["docs"]), "docs_2")
        XCTAssertEqual(Slug.make(from: "Docs", existing: ["docs", "docs_2"]), "docs_3")
    }

    func testFileInfoDerivesNameAndExt() {
        let url = URL(fileURLWithPath: "/tmp/Invoice March.PDF")
        let f = FileInfo(id: "f0", url: url)
        XCTAssertEqual(f.name, "Invoice March")
        XCTAssertEqual(f.ext, "pdf")
        XCTAssertEqual(f.displayName, "Invoice March.PDF")
    }

    func testClassifierErrorMessages() {
        XCTAssertEqual(ClassifierError.notConfigured("x").message, "x")
        XCTAssertEqual(ClassifierError.unavailable("HTTP 529").message, "Classification unavailable: HTTP 529")
        XCTAssertEqual(ClassifierError.badRequest("bad").message, "Classifier rejected request: bad")
    }
}
