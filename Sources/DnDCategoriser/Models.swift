import Foundation

struct Folder: Codable, Identifiable, Equatable {
    var id: String          // stable slug, used as the classifier criteria key
    var path: URL
    var name: String
    var description: String // user-written task description, sent to the classifier
}

struct FileInfo: Identifiable, Equatable {
    var id: String          // "f0", "f1", ... per drag session
    var url: URL
    var name: String        // last path component without extension
    var ext: String         // lowercase extension, "" if none
    var sizeBytes: Int64

    init(id: String, url: URL, name: String, ext: String, sizeBytes: Int64) {
        self.id = id
        self.url = url
        self.name = name
        self.ext = ext
        self.sizeBytes = sizeBytes
    }

    init(id: String, url: URL) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        let size = values?.fileSize ?? values?.totalFileAllocatedSize ?? 0
        self.init(
            id: id,
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            ext: url.pathExtension.lowercased(),
            sizeBytes: Int64(size)
        )
    }

    var displayName: String { url.lastPathComponent }
}

enum Engine: String, Codable, CaseIterable {
    case jev
    case onDevice
}

/// Which per-file facts are put in the classifier payload. `name` is always sent.
enum FileField: String, Codable, CaseIterable, Identifiable {
    case name, ext, size, kind, created, modified, parent, snippet
    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return "File name"
        case .ext: return "Extension"
        case .size: return "Size (KB)"
        case .kind: return "Kind (e.g. PDF document)"
        case .created: return "Created date"
        case .modified: return "Modified date"
        case .parent: return "Parent folder name"
        case .snippet: return "First 512 bytes of text content"
        }
    }

    var warning: String? {
        switch self {
        case .snippet: return "Sends file content to the classifier"
        case .parent: return "Reveals folder names from your disk"
        default: return nil
        }
    }
}

/// Everything user-editable about what the classifier receives. Folder names and descriptions come from `Folder`.
struct PayloadTemplate: Codable, Equatable {
    static let defaultTask = "The user is dragging files onto task folders. Decide which folder each file belongs in."
    static let defaultQuestion = "Which folder is the best home for this file?"
    static let defaultNoneDescription = "Does not belong in any of the listed folders"
    static let defaultModel = "jev-latest"
    static let defaultFields: Set<FileField> = [.name, .ext, .size]

    var task = defaultTask
    var question = defaultQuestion
    var noneDescription = defaultNoneDescription
    var model = defaultModel
    var timeoutSeconds: Double = 3
    var fields = defaultFields

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        task = try c.decodeIfPresent(String.self, forKey: .task) ?? Self.defaultTask
        question = try c.decodeIfPresent(String.self, forKey: .question) ?? Self.defaultQuestion
        noneDescription = try c.decodeIfPresent(String.self, forKey: .noneDescription) ?? Self.defaultNoneDescription
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? Self.defaultModel
        timeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 3
        fields = try c.decodeIfPresent(Set<FileField>.self, forKey: .fields) ?? Self.defaultFields
        fields.insert(.name)
    }
}

struct Config: Codable, Equatable {
    var folders: [Folder] = []
    var engine: Engine = .jev
    var showInDock: Bool = false
    var payload = PayloadTemplate()
    var logRequests: Bool = false
    var edge: ShelfEdge = .right

    init(folders: [Folder] = [], engine: Engine = .jev, showInDock: Bool = false,
         payload: PayloadTemplate = PayloadTemplate(), logRequests: Bool = false, edge: ShelfEdge = .right) {
        self.folders = folders
        self.engine = engine
        self.showInDock = showInDock
        self.payload = payload
        self.logRequests = logRequests
        self.edge = edge
    }

    /// Every key optional so a config.json written by an older build still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        folders = try c.decodeIfPresent([Folder].self, forKey: .folders) ?? []
        engine = try c.decodeIfPresent(Engine.self, forKey: .engine) ?? .jev
        showInDock = try c.decodeIfPresent(Bool.self, forKey: .showInDock) ?? false
        payload = try c.decodeIfPresent(PayloadTemplate.self, forKey: .payload) ?? PayloadTemplate()
        logRequests = try c.decodeIfPresent(Bool.self, forKey: .logRequests) ?? false
        edge = try c.decodeIfPresent(ShelfEdge.self, forKey: .edge) ?? .right
    }
}

enum ClassifierError: Error, Equatable {
    case notConfigured(String)
    case badRequest(String)
    case unavailable(String)

    var message: String {
        switch self {
        case .notConfigured(let m): return m
        case .badRequest(let m): return "Classifier rejected request: \(m)"
        case .unavailable(let m): return "Classification unavailable: \(m)"
        }
    }
}

/// Maps each file id to the chosen folder id. A missing file id means "none".
protocol Classifier {
    func classify(files: [FileInfo], folders: [Folder]) async throws -> [String: String]
}

enum Slug {
    static let reserved = "none"

    static func make(from name: String, existing: Set<String>) -> String {
        let replaced = name.lowercased().map { ch -> String in
            (ch.isLetter || ch.isNumber) ? String(ch) : "_"
        }.joined()
        var base = replaced
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
        if base.isEmpty { base = "folder" }
        if base == reserved { base = "none_folder" }
        var candidate = base
        var n = 2
        while existing.contains(candidate) {
            candidate = "\(base)_\(n)"
            n += 1
        }
        return candidate
    }
}
