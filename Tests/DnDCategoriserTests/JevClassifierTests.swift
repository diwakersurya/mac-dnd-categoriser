import XCTest
@testable import DnDCategoriser

final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let (status, data) = Self.handler!(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class JevClassifierTests: XCTestCase {
    let files = [
        FileInfo(id: "f0", url: URL(fileURLWithPath: "/x/invoice_march.pdf"), name: "invoice_march", ext: "pdf", sizeBytes: 231 * 1024),
        FileInfo(id: "f1", url: URL(fileURLWithPath: "/x/Screenshot.png"), name: "Screenshot", ext: "png", sizeBytes: 500),
    ]
    let folders = [
        Folder(id: "invoices", path: URL(fileURLWithPath: "/a"), name: "Invoices", description: "Supplier invoices"),
        Folder(id: "bug_shots", path: URL(fileURLWithPath: "/b"), name: "Bug Screenshots", description: "Screenshots for bug reports"),
    ]

    var session: URLSession!
    var classifier: JevClassifier!

    override func setUp() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: cfg)
        StubURLProtocol.requests = []
        StubURLProtocol.handler = nil
        classifier = JevClassifier(apiKey: { "sk-test" }, session: session)
        classifier.retryDelayNanos = 1_000
    }

    private func json(_ any: Any) -> Data { try! JSONSerialization.data(withJSONObject: any) }

    func testRequestEncodingShape() throws {
        let req = JevRequest(files: files, folders: folders)
        let data = try JSONEncoder().encode(req)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(obj["model"] as? String, "jev-latest")

        let state = try XCTUnwrap(obj["state"] as? [String: Any])
        let stateFiles = try XCTUnwrap(state["files"] as? [[String: Any]])
        XCTAssertEqual(stateFiles.count, 2)
        XCTAssertEqual(stateFiles[0]["id"] as? String, "f0")
        XCTAssertEqual(stateFiles[0]["size_kb"] as? Int, 231)
        XCTAssertEqual(stateFiles[1]["size_kb"] as? Int, 1) // rounds up to at least 1

        let questions = try XCTUnwrap(obj["questions"] as? [String: Any])
        XCTAssertEqual(Set(questions.keys), ["f0", "f1"])
        let q0 = try XCTUnwrap(questions["f0"] as? [String: Any])
        XCTAssertEqual(q0["type"] as? String, "choice")
        let instr = try XCTUnwrap(q0["instructions"] as? [String: Any])
        XCTAssertEqual((instr["file"] as? [String: Any])?["name"] as? String, "invoice_march")
        XCTAssertNotNil(instr["question"] as? String)
        let criteria = try XCTUnwrap(q0["criteria"] as? [String: Any])
        XCTAssertEqual(Set(criteria.keys), ["invoices", "bug_shots", "none"])
        XCTAssertEqual((criteria["invoices"] as? [String: Any])?["what"] as? String, "Supplier invoices")
        XCTAssertEqual((criteria["invoices"] as? [String: Any])?["name"] as? String, "Invoices")
        XCTAssertEqual(criteria["none"] as? String, "Does not belong in any of the listed folders")
    }

    func testSuccessMapsChoicesAndDropsNoneAndUnknown() async throws {
        StubURLProtocol.handler = { _ in
            (200, self.json([
                "model": "jev-1.13.0",
                "answers": [
                    "f0": ["type": "choice", "choice": "invoices", "confidence": 0.97, "probabilities": ["invoices": 0.97, "bug_shots": 0.02, "none": 0.01]],
                    "f1": ["type": "choice", "choice": "none", "confidence": 0.8, "probabilities": ["invoices": 0.1, "bug_shots": 0.1, "none": 0.8]],
                ],
                "usage": ["input_tokens": 210, "output_tokens": 31],
            ]))
        }
        let result = try await classifier.classify(files: files, folders: folders)
        XCTAssertEqual(result, ["f0": "invoices"])
        let sent = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://api.typesafe.ai/v1/systemone")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testMissingAnswerMeansNone() async throws {
        StubURLProtocol.handler = { _ in
            (200, self.json(["model": "jev-1.13.0", "answers": ["f0": ["type": "choice", "choice": "bug_shots"]]]))
        }
        let result = try await classifier.classify(files: files, folders: folders)
        XCTAssertEqual(result, ["f0": "bug_shots"])
    }

    func testMissingKeyThrowsWithoutNetwork() async {
        let c = JevClassifier(apiKey: { nil }, session: session)
        do {
            _ = try await c.classify(files: files, folders: folders)
            XCTFail("expected throw")
        } catch let e as ClassifierError {
            XCTAssertEqual(e, .notConfigured("Add a TypeSafe API key in Settings"))
        } catch { XCTFail("wrong error \(error)") }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testUnauthorizedMapsToNotConfigured() async {
        StubURLProtocol.handler = { _ in (401, Data()) }
        do {
            _ = try await classifier.classify(files: files, folders: folders)
            XCTFail("expected throw")
        } catch let e as ClassifierError {
            XCTAssertEqual(e, .notConfigured("API key rejected"))
        } catch { XCTFail("wrong error \(error)") }
    }

    func testValidationErrorMapsToBadRequest() async {
        StubURLProtocol.handler = { _ in (422, Data("criteria required".utf8)) }
        do {
            _ = try await classifier.classify(files: files, folders: folders)
            XCTFail("expected throw")
        } catch let e as ClassifierError {
            XCTAssertEqual(e, .badRequest("criteria required"))
        } catch { XCTFail("wrong error \(error)") }
    }

    func testRateLimitRetriesOnceThenUnavailable() async {
        StubURLProtocol.handler = { _ in (429, Data()) }
        do {
            _ = try await classifier.classify(files: files, folders: folders)
            XCTFail("expected throw")
        } catch let e as ClassifierError {
            XCTAssertEqual(e, .unavailable("HTTP 429"))
        } catch { XCTFail("wrong error \(error)") }
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
    }

    func testRateLimitThenSuccess() async throws {
        var calls = 0
        StubURLProtocol.handler = { _ in
            calls += 1
            if calls == 1 { return (529, Data()) }
            return (200, self.json(["model": "jev-1.13.0", "answers": ["f0": ["type": "choice", "choice": "invoices"]]]))
        }
        let result = try await classifier.classify(files: files, folders: folders)
        XCTAssertEqual(result, ["f0": "invoices"])
    }

    func testEmptyInputsShortCircuit() async throws {
        let result = try await classifier.classify(files: [], folders: folders)
        XCTAssertEqual(result, [:])
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }
}
