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

struct Config: Codable, Equatable {
    var folders: [Folder] = []
    var engine: Engine = .jev
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
