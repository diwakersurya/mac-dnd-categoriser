import Foundation
import Combine

/// Renders exactly what a classifier would receive, from the same builders the classifiers use.
enum PayloadPreview {
    static let sampleFiles: [FileInfo] = [
        FileInfo(id: "f0", url: URL(fileURLWithPath: "/Users/you/Downloads/invoice_march_2026.pdf"), name: "invoice_march_2026", ext: "pdf", sizeBytes: 231 * 1024),
        FileInfo(id: "f1", url: URL(fileURLWithPath: "/Users/you/Desktop/Screenshot 2026-09-21 at 10.03.12.png"), name: "Screenshot 2026-09-21 at 10.03.12", ext: "png", sizeBytes: 1_800_000),
        FileInfo(id: "f2", url: URL(fileURLWithPath: "/Users/you/Documents/notes.txt"), name: "notes", ext: "txt", sizeBytes: 900),
    ]

    static func render(engine: Engine, files: [FileInfo], folders: [Folder], template: PayloadTemplate) -> String {
        switch engine {
        case .jev:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = (try? encoder.encode(JevRequest(files: files, folders: folders, template: template))) ?? Data()
            return String(decoding: data, as: UTF8.self)
        case .onDevice:
            let text = OnDeviceClassifier.prompt(files: files, folders: folders, template: template)
            return "INSTRUCTIONS\n\(text.instructions)\n\nPROMPT\n\(text.prompt)"
        }
    }

    /// Rough: about four characters per token.
    static func estimatedTokens(_ text: String) -> Int { max(1, text.count / 4) }
}

struct RequestLogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let engine: Engine
    let latency: TimeInterval
    let request: String
    let response: String
}

/// Per-launch memory shared between the shelf and Settings: files from the last drag (for the preview)
/// and, when enabled, the last ten request/response pairs. Nothing here is persisted.
@MainActor
final class SessionLog: ObservableObject {
    @Published var lastFiles: [FileInfo] = []
    @Published var entries: [RequestLogEntry] = []

    func record(_ entry: RequestLogEntry) {
        entries.insert(entry, at: 0)
        if entries.count > 10 { entries.removeLast(entries.count - 10) }
    }
}
