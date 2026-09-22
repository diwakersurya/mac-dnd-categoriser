import Foundation
import UniformTypeIdentifiers

/// Optional per-file facts, read on demand only when the template asks for them. Each returns nil when unavailable.
enum FileMetadata {
    static func kind(_ url: URL) -> String? {
        (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.localizedDescription
    }

    static func created(_ url: URL) -> String? {
        (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate.map(iso)
    }

    static func modified(_ url: URL) -> String? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate.map(iso)
    }

    static func parent(_ url: URL) -> String? {
        let name = url.deletingLastPathComponent().lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    /// Leading bytes decoded as UTF-8, only if they look like text. Binary files yield nil.
    static func snippet(_ url: URL, bytes: Int = 512) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: bytes), !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return nil }
        let scalars = text.unicodeScalars
        let printable = scalars.filter { $0.value >= 32 || $0 == "\n" || $0 == "\t" || $0 == "\r" }.count
        guard Double(printable) >= 0.9 * Double(scalars.count) else { return nil }
        return text
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
