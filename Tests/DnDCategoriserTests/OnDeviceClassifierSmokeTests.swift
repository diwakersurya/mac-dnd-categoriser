import XCTest
@testable import DnDCategoriser

/// Talks to the real Apple on-device model. Opt in with `RUN_ONDEVICE=1 swift test --filter OnDevice`.
final class OnDeviceClassifierSmokeTests: XCTestCase {
    func testAssignsObviousFiles() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_ONDEVICE"] == "1", "set RUN_ONDEVICE=1 to run")
        let files = [
            FileInfo(id: "f0", url: URL(fileURLWithPath: "/x/invoice_march_2026.pdf"), name: "invoice_march_2026", ext: "pdf", sizeBytes: 231 * 1024),
            FileInfo(id: "f1", url: URL(fileURLWithPath: "/x/Screenshot 2026-09-21 at 10.03.12.png"), name: "Screenshot 2026-09-21 at 10.03.12", ext: "png", sizeBytes: 1_800_000),
            FileInfo(id: "f2", url: URL(fileURLWithPath: "/x/holiday_playlist.m3u"), name: "holiday_playlist", ext: "m3u", sizeBytes: 900),
        ]
        let folders = [
            Folder(id: "invoices", path: URL(fileURLWithPath: "/a"), name: "Invoices", description: "Supplier invoices, receipts, bills"),
            Folder(id: "bug_shots", path: URL(fileURLWithPath: "/b"), name: "Bug Screenshots", description: "Screenshots and screen recordings for bug reports"),
        ]
        let start = Date()
        let result = try await OnDeviceClassifier().classify(files: files, folders: folders)
        print("on-device result: \(result) in \(Date().timeIntervalSince(start))s")
        XCTAssertEqual(result["f0"], "invoices")
        XCTAssertEqual(result["f1"], "bug_shots")
        XCTAssertNil(result["f2"])
    }
}
