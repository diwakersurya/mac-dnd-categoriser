import Foundation
import FoundationModels

@Generable
struct OnDeviceAssignment {
    @Guide(description: "The file id exactly as listed, e.g. f0")
    var fileID: String
    @Guide(description: "The folder id exactly as listed, or none")
    var folderID: String
}

@Generable
struct OnDeviceAssignments {
    var items: [OnDeviceAssignment]
}

/// Apple Foundation Models (macOS 26) guided generation. Slower than Jev (1–3 s), fully offline.
final class OnDeviceClassifier: Classifier {
    private let template: PayloadTemplate

    init(template: PayloadTemplate = PayloadTemplate()) {
        self.template = template
    }

    /// The exact text the model receives; also used by the Settings preview.
    static func prompt(files: [FileInfo], folders: [Folder], template: PayloadTemplate) -> (instructions: String, prompt: String) {
        let folderLines = folders.map { "- \($0.id): \($0.name). \($0.description)" }.joined(separator: "\n")
        let instructions = """
        \(template.task)
        Folders:
        \(folderLines)
        - none: \(template.noneDescription)
        \(template.question) For every file, output its fileID and the single best folderID. Use only ids from the list. Output exactly one item per file.
        """
        let fileLines = files.map { file -> String in
            let entry = JevRequest.FileEntry(file, fields: template.fields)
            var parts = ["- \(file.id): \"\(file.name)\""]
            if let e = entry.ext { parts.append("ext=\(e.isEmpty ? "-" : e)") }
            if let s = entry.size_kb { parts.append("size_kb=\(s)") }
            if let k = entry.kind { parts.append("kind=\"\(k)\"") }
            if let c = entry.created { parts.append("created=\(c)") }
            if let m = entry.modified { parts.append("modified=\(m)") }
            if let p = entry.parent { parts.append("parent=\"\(p)\"") }
            if let t = entry.snippet { parts.append("snippet=\"\(t.replacingOccurrences(of: "\n", with: " "))\"") }
            return parts.joined(separator: " ")
        }.joined(separator: "\n")
        return (instructions, "Files:\n\(fileLines)")
    }

    func classify(files: [FileInfo], folders: [Folder]) async throws -> [String: String] {
        guard !files.isEmpty, !folders.isEmpty else { return [:] }

        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw ClassifierError.notConfigured("On-device model unavailable: \(reason)")
        }

        let text = Self.prompt(files: files, folders: folders, template: template)
        let session = LanguageModelSession(instructions: text.instructions)
        let items: [OnDeviceAssignment]
        do {
            // Greedy sampling: classification should be deterministic, not creative.
            items = try await session.respond(
                to: text.prompt,
                generating: OnDeviceAssignments.self,
                options: GenerationOptions(sampling: .greedy)
            ).content.items
        } catch {
            throw ClassifierError.unavailable(error.localizedDescription)
        }

        let knownByLowercase = Dictionary(folders.map { ($0.id.lowercased(), $0.id) }, uniquingKeysWith: { a, _ in a })
        let fileIDs = Set(files.map(\.id))
        var result: [String: String] = [:]
        for item in items {
            let fileID = item.fileID.trimmingCharacters(in: .whitespaces)
            guard fileIDs.contains(fileID),
                  let folderID = knownByLowercase[item.folderID.trimmingCharacters(in: .whitespaces).lowercased()] else { continue }
            result[fileID] = folderID
        }
        return result
    }
}
