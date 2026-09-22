import Foundation

/// Body for POST https://api.typesafe.ai/v1/systemone.
/// One Choice question per file; all questions share the same criteria (one key per folder + "none").
struct JevRequest: Encodable {
    static let noneKey = "none"
    static let noneDescription = "Does not belong in any of the listed folders"

    struct FileEntry: Encodable {
        let id: String
        let name: String
        let ext: String
        let size_kb: Int64
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

    init(files: [FileInfo], folders: [Folder], model: String = "jev-latest") {
        let entries = files.map {
            FileEntry(id: $0.id, name: $0.name, ext: $0.ext, size_kb: max(1, $0.sizeBytes / 1024))
        }
        var criteria: [String: CriterionValue] = [:]
        for folder in folders {
            criteria[folder.id] = .folder(FolderCriterion(name: folder.name, what: folder.description))
        }
        criteria[Self.noneKey] = .text(Self.noneDescription)

        self.model = model
        self.state = State(
            task: "The user is dragging files onto task folders. Decide which folder each file belongs in.",
            files: entries
        )
        var questions: [String: Question] = [:]
        for entry in entries {
            questions[entry.id] = Question(
                instructions: Instructions(file: entry, question: "Which folder is the best home for this file?"),
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
    let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    var timeout: TimeInterval = 3
    var retryDelayNanos: UInt64 = 400_000_000

    private let apiKey: () -> String?
    private let session: URLSession

    init(apiKey: @escaping () -> String?, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func classify(files: [FileInfo], folders: [Folder]) async throws -> [String: String] {
        guard let key = apiKey(), !key.isEmpty else {
            throw ClassifierError.notConfigured("Add a TypeSafe API key in Settings")
        }
        guard !files.isEmpty, !folders.isEmpty else { return [:] }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(JevRequest(files: files, folders: folders))

        let (data, status) = try await send(request, allowRetry: true)
        switch status {
        case 200..<300: break
        case 401: throw ClassifierError.notConfigured("API key rejected")
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
