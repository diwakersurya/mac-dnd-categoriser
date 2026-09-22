import Foundation
import Combine

enum TileState: Equatable {
    case idle
    case pending
    case matches([FileInfo])
    case empty
    case failed(String)
}

struct Tile: Identifiable, Equatable {
    let folder: Folder
    var state: TileState
    var missing: Bool
    var id: String { folder.id }
}

@MainActor
final class ShelfViewModel: ObservableObject {
    static let missingMessage = "Missing folder"

    @Published var tiles: [Tile] = []
    @Published var activeIndex: Int?
    @Published var flashIndex: Int?
    @Published var engineLabel: String = ""
    var onAddFolder: (() -> Void)?

    /// Folders whose path exists; these are what the classifier is asked about.
    var activeFolders: [Folder] { tiles.filter { !$0.missing }.map(\.folder) }

    func reset(folders: [Folder], engine: Engine) {
        tiles = folders.map { folder in
            let exists = FileManager.default.fileExists(atPath: folder.path.path)
            return Tile(folder: folder, state: exists ? .idle : .failed(Self.missingMessage), missing: !exists)
        }
        engineLabel = engine == .jev ? "Jev" : "On-device"
        activeIndex = nil
        flashIndex = nil
    }

    func beginSession() {
        for i in tiles.indices where !tiles[i].missing { tiles[i].state = .pending }
    }

    func apply(results: [String: String], files: [FileInfo]) {
        for i in tiles.indices where !tiles[i].missing {
            let matched = files.filter { results[$0.id] == tiles[i].folder.id }
            tiles[i].state = matched.isEmpty ? .empty : .matches(matched)
        }
    }

    func fail(_ message: String) {
        for i in tiles.indices where !tiles[i].missing { tiles[i].state = .failed(message) }
    }

    func matchedFiles(at index: Int) -> [FileInfo]? {
        guard tiles.indices.contains(index), case .matches(let files) = tiles[index].state else { return nil }
        return files
    }

    func flash(_ index: Int) {
        flashIndex = index
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if self?.flashIndex == index { self?.flashIndex = nil }
        }
    }
}
