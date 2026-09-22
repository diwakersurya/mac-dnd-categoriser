import XCTest
@testable import DnDCategoriser

final class PayloadTests: XCTestCase {
    let files = [
        FileInfo(id: "f0", url: URL(fileURLWithPath: "/x/invoice_march.pdf"), name: "invoice_march", ext: "pdf", sizeBytes: 231 * 1024),
    ]
    let folders = [
        Folder(id: "invoices", path: URL(fileURLWithPath: "/a"), name: "Invoices", description: "Supplier invoices"),
    ]

    func testConfigWithoutPayloadKeyLoadsDefaults() throws {
        let json = #"{"engine":"jev","folders":[]}"#
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(c.payload, PayloadTemplate())
        XCTAssertFalse(c.logRequests)
        XCTAssertEqual(c.payload.fields, [.name, .ext, .size])
        XCTAssertEqual(c.payload.model, "jev-latest")
    }

    func testPayloadTemplateRoundTrips() throws {
        var t = PayloadTemplate()
        t.task = "T"
        t.fields = [.name, .kind]
        t.timeoutSeconds = 5
        let data = try JSONEncoder().encode(t)
        XCTAssertEqual(try JSONDecoder().decode(PayloadTemplate.self, from: data), t)
    }

    func testTemplateControlsTextsModelAndFields() throws {
        var t = PayloadTemplate()
        t.task = "Sort these."
        t.question = "Where does it go?"
        t.noneDescription = "Nowhere"
        t.model = "jev-1.13.0"
        t.fields = [.name]
        let data = try JSONEncoder().encode(JevRequest(files: files, folders: folders, template: t))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["model"] as? String, "jev-1.13.0")
        let state = try XCTUnwrap(obj["state"] as? [String: Any])
        XCTAssertEqual(state["task"] as? String, "Sort these.")
        let entry = try XCTUnwrap((state["files"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(entry.keys), ["id", "name"])
        let q = try XCTUnwrap((obj["questions"] as? [String: Any])?["f0"] as? [String: Any])
        XCTAssertEqual((q["instructions"] as? [String: Any])?["question"] as? String, "Where does it go?")
        XCTAssertEqual((q["criteria"] as? [String: Any])?["none"] as? String, "Nowhere")
    }

    func testMetadataFieldsForRealFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PayloadTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let text = dir.appendingPathComponent("notes.txt")
        try "hello world\nsecond line".write(to: text, atomically: true, encoding: .utf8)
        let bin = dir.appendingPathComponent("blob.bin")
        try Data((0..<600).map { _ in UInt8.random(in: 0...255) }).write(to: bin)

        XCTAssertEqual(FileMetadata.snippet(text), "hello world\nsecond line")
        XCTAssertNil(FileMetadata.snippet(bin))
        XCTAssertEqual(FileMetadata.parent(text), dir.lastPathComponent)
        XCTAssertNotNil(FileMetadata.modified(text))
        XCTAssertNotNil(FileMetadata.kind(text))

        var t = PayloadTemplate()
        t.fields = [.name, .snippet, .parent]
        let data = try JSONEncoder().encode(JevRequest(files: [FileInfo(id: "f0", url: text)], folders: folders, template: t))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entry = try XCTUnwrap(((obj["state"] as? [String: Any])?["files"] as? [[String: Any]])?.first)
        XCTAssertEqual(entry["snippet"] as? String, "hello world\nsecond line")
        XCTAssertEqual(entry["parent"] as? String, dir.lastPathComponent)
        XCTAssertNil(entry["size_kb"])
    }

    func testPreviewRendersJSONForJevAndPromptForOnDevice() throws {
        let jev = PayloadPreview.render(engine: .jev, files: files, folders: folders, template: PayloadTemplate())
        let obj = try JSONSerialization.jsonObject(with: Data(jev.utf8)) as? [String: Any]
        XCTAssertEqual(obj?["model"] as? String, "jev-latest")
        XCTAssertTrue(jev.contains("\n")) // pretty printed

        let local = PayloadPreview.render(engine: .onDevice, files: files, folders: folders, template: PayloadTemplate())
        XCTAssertTrue(local.contains("- invoices: Invoices. Supplier invoices"))
        XCTAssertTrue(local.contains("f0"))
        XCTAssertGreaterThan(PayloadPreview.estimatedTokens(jev), 20)
    }
}
