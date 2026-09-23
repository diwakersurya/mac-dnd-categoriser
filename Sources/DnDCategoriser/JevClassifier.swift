import Foundation

/// Body for POST to the configured Jev URL (TypeSafe System One API, default https://api.typesafe.ai/v1/systemone).
/// One Choice question per file; all questions share the same criteria (one key per folder + "none").
struct JevRequest: Encodable {
    static let noneKey = "none"

    /// Optional members encode only when present, so the template's field set controls the JSON shape.
    struct FileEntry: Encodable {
        let id: String
        var name: String?
        var ext: String?
        var size_kb: Int64?
        var kind: String?
        var created: String?
        var modified: String?
        var parent: String?
        var snippet: String?

        init(_ f: FileInfo, fields: Set<FileField>) {
            id = f.id
            name = f.name
            if fields.contains(.ext) { ext = f.ext }
            if fields.contains(.size) { size_kb = max(1, f.sizeBytes / 1024) }
            if fields.contains(.kind) { kind = FileMetadata.kind(f.url) }
            if fields.contains(.created) { created = FileMetadata.created(f.url) }
            if fields.contains(.modified) { modified = FileMetadata.modified(f.url) }
            if fields.contains(.parent) { parent = FileMetadata.parent(f.url) }
            if fields.contains(.snippet) { snippet = FileMetadata.snippet(f.url) }
        }
    }

    struct State: Encodable {
        let task: String
        let files: [FileEntry]
    }

    struct Instructions: Encodable {
        let file: FileEntry
        let question: String
    }

    struct FolderCriterion: Encodable {
        let name: String
        let what: String
    }

    enum CriterionValue: Encodable {
        case folder(FolderCriterion)
        case text(String)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .folder(let f): try container.encode(f)
            case .text(let s): try container.encode(s)
            }
        }
    }

    struct Question: Encodable {
        let type = "choice"
        let instructions: Instructions
        let criteria: [String: CriterionValue]
    }

    let model: String
    let state: State
    let questions: [String: Question]

    init(files: [FileInfo], folders: [Folder], template: PayloadTemplate = PayloadTemplate()) {
        let entries = files.map { FileEntry($0, fields: template.fields) }
        var criteria: [String: CriterionValue] = [:]
        for folder in folders {
            criteria[folder.id] = .folder(FolderCriterion(name: folder.name, what: folder.description))
        }
        criteria[Self.noneKey] = .text(template.noneDescription)

        self.model = template.model
        self.state = State(task: template.task, files: entries)
        var questions: [String: Question] = [:]
        for entry in entries {
            questions[entry.id] = Question(
                instructions: Instructions(file: entry, question: template.question),
                criteria: criteria
            )
        }
        self.questions = questions
    }
}

struct JevResponse: Decodable {
    struct Answer: Decodable {
        let type: String
        let choice: String?
        let confidence: Double?
        let probabilities: [String: Double]?
    }
    let model: String
    let answers: [String: Answer]
}

final class JevClassifier: Classifier {
    var retryDelayNanos: UInt64 = 400_000_000

    private let apiKey: () -> String?
    private let session: URLSession
    private let template: PayloadTemplate

    init(apiKey: @escaping () -> String?, session: URLSession = .shared, template: PayloadTemplate = PayloadTemplate()) {
        self.apiKey = apiKey
        self.session = session
        self.template = template
    }

    func classify(files: [FileInfo], folders: [Folder]) async throws -> [String: String] {
        guard let endpoint = template.endpointURL else {
            throw ClassifierError.notConfigured("Jev URL must start with http:// or https://")
        }
        let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Hosted TypeSafe always needs a key, so fail before anything leaves the machine.
        // Other servers decide for themselves; an empty key simply omits the header.
        if key.isEmpty && template.usesDefaultEndpoint {
            throw ClassifierError.notConfigured("Add a TypeSafe API key in Settings")
        }
        guard !files.isEmpty, !folders.isEmpty else { return [:] }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = max(0.5, template.timeoutSeconds)
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(JevRequest(files: files, folders: folders, template: template))

        let (data, status) = try await send(request, allowRetry: true)
        switch status {
        case 200..<300: break
        case 401: throw ClassifierError.notConfigured("API key missing or rejected")
        case 422: throw ClassifierError.badRequest(String(decoding: data, as: UTF8.self))
        default: throw ClassifierError.unavailable("HTTP \(status)")
        }

        let decoded: JevResponse
        do { decoded = try JSONDecoder().decode(JevResponse.self, from: data) }
        catch { throw ClassifierError.unavailable("Unreadable response") }

        let known = Set(folders.map(\.id))
        var result: [String: String] = [:]
        for file in files {
            if let choice = decoded.answers[file.id]?.choice, known.contains(choice) {
                result[file.id] = choice
            }
        }
        return result
    }

    private func send(_ request: URLRequest, allowRetry: Bool) async throws -> (Data, Int) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClassifierError.unavailable(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if allowRetry && (status == 429 || status == 529) {
            try? await Task.sleep(nanoseconds: retryDelayNanos)
            return try await send(request, allowRetry: false)
        }
        return (data, status)
    }
}
