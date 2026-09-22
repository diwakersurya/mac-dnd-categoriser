import Foundation

struct MoveResult: Equatable {
    var moved: [URL: URL] = [:]     // source -> destination
    var failed: [URL: String] = [:] // source -> error description
}

enum FileMover {
    /// Moves each source in order. `afterEach(done, total)` fires after every file, on the calling thread.
    static func move(_ sources: [URL], into folder: URL, fileManager: FileManager = .default,
                     afterEach: ((Int, Int) -> Void)? = nil) -> MoveResult {
        var result = MoveResult()
        for (i, source) in sources.enumerated() {
            let destination = availableDestination(for: source, in: folder, fileManager: fileManager)
            do {
                try fileManager.moveItem(at: source, to: destination)
                result.moved[source] = destination
            } catch {
                result.failed[source] = error.localizedDescription
            }
            afterEach?(i + 1, sources.count)
        }
        return result
    }

    /// `name.ext`, then `name (2).ext`, `name (3).ext`, ... until free.
    static func availableDestination(for source: URL, in folder: URL, fileManager: FileManager = .default) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var candidate = folder.appendingPathComponent(source.lastPathComponent)
        var n = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            candidate = folder.appendingPathComponent(name)
            n += 1
        }
        return candidate
    }
}
