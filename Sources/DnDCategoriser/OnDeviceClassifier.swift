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
    func classify(files: [FileInfo], folders: [Folder]) async throws -> [String: String] {
        guard !files.isEmpty, !folders.isEmpty else { return [:] }

        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw ClassifierError.notConfigured("On-device model unavailable: \(reason)")
        }

        let folderLines = folders.map { "- \($0.id): \($0.name). \($0.description)" }.joined(separator: "\n")
        let instructions = """
        You sort files into task folders based only on file name, extension and size.
        Folders:
        \(folderLines)
        - none: does not belong in any listed folder
        For every file, output its fileID and the single best folderID. Use only ids from the list. Output exactly one item per file.
        """
        let fileLines = files.map {
            "- \($0.id): \"\($0.name)\" ext=\($0.ext.isEmpty ? "-" : $0.ext) size_kb=\(max(1, $0.sizeBytes / 1024))"
        }.joined(separator: "\n")

        let session = LanguageModelSession(instructions: instructions)
        let items: [OnDeviceAssignment]
        do {
            items = try await session.respond(to: "Files:\n\(fileLines)", generating: OnDeviceAssignments.self).content.items
        } catch {
            throw ClassifierError.unavailable(error.localizedDescription)
        }

        let known = Set(folders.map(\.id))
        let fileIDs = Set(files.map(\.id))
        var result: [String: String] = [:]
        for item in items where fileIDs.contains(item.fileID) && known.contains(item.folderID) {
            result[item.fileID] = item.folderID
        }
        return result
    }
}
