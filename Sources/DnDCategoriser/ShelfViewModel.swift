import Foundation
import Combine

enum TileState: Equatable {
    case idle
    case pending
    case matches([FileInfo])
    case empty
    case failed(String)
    case moving(done: Int, total: Int)
    case done(moved: Int, failed: Int)
}

struct MovePlanEntry: Equatable {
    var index: Int
    var files: [FileInfo]
}

struct Tile: Identifiable, Equatable {
    let folder: Folder
    var state: TileState
    var missing: Bool
    var id: String { folder.id }
}

struct FlyoutContent: Equatable {
    var title: String
    var files: [FileInfo]
}

/// Slots on the shelf are the folder tiles (0..<tiles.count) plus, when some dragged files matched nothing,
/// one trailing "No folder" slot at index tiles.count. All slots share the tile height so layout math stays fixed.
@MainActor
final class ShelfViewModel: ObservableObject {
    static let missingMessage = "Missing folder"
    static let unmatchedTitle = "No folder"

    @Published var tiles: [Tile] = []
    @Published var unmatched: [FileInfo] = []
    @Published var activeIndex: Int?
    @Published var flashIndex: Int?
    @Published var engineLabel: String = ""

    /// Folders whose path exists; these are what the classifier is asked about.
    var activeFolders: [Folder] { tiles.filter { !$0.missing }.map(\.folder) }
    var slotCount: Int { tiles.count + (unmatched.isEmpty ? 0 : 1) }
    var unmatchedSlot: Int? { unmatched.isEmpty ? nil : tiles.count }

    func reset(folders: [Folder], engine: Engine) {
        tiles = folders.map { folder in
            let exists = FileManager.default.fileExists(atPath: folder.path.path)
            return Tile(folder: folder, state: exists ? .idle : .failed(Self.missingMessage), missing: !exists)
        }
        unmatched = []
        engineLabel = engine == .jev ? "Jev" : "On-device"
        activeIndex = nil
        flashIndex = nil
    }

    func beginSession() {
        for i in tiles.indices where !tiles[i].missing { tiles[i].state = .pending }
        unmatched = []
    }

    func apply(results: [String: String], files: [FileInfo]) {
        for i in tiles.indices where !tiles[i].missing {
            let matched = files.filter { results[$0.id] == tiles[i].folder.id }
            tiles[i].state = matched.isEmpty ? .empty : .matches(matched)
        }
        let assigned = Set(tiles.flatMap { tile -> [String] in
            if case .matches(let files) = tile.state { return files.map(\.id) }
            return []
        })
        unmatched = files.filter { !assigned.contains($0.id) }
    }

    func fail(_ message: String) {
        for i in tiles.indices where !tiles[i].missing { tiles[i].state = .failed(message) }
        unmatched = []
    }

    func matchedFiles(at index: Int) -> [FileInfo]? {
        guard tiles.indices.contains(index), case .matches(let files) = tiles[index].state else { return nil }
        return files
    }

    func flyout(forSlot index: Int) -> FlyoutContent? {
        if index == unmatchedSlot { return FlyoutContent(title: Self.unmatchedTitle, files: unmatched) }
        guard let files = matchedFiles(at: index) else { return nil }
        return FlyoutContent(title: tiles[index].folder.name, files: files)
    }

    /// Classification finished for every usable tile (no pending, no failure). Drop is accepted only then.
    var isReady: Bool {
        let usable = tiles.filter { !$0.missing }
        guard !usable.isEmpty else { return false }
        return usable.allSatisfy { tile in
            switch tile.state {
            case .matches, .empty, .moving, .done: return true
            case .idle, .pending, .failed: return false
            }
        }
    }

    var isMoving: Bool {
        tiles.contains { if case .moving = $0.state { return true }; return false }
    }

    var movePlan: [MovePlanEntry] {
        tiles.indices.compactMap { i in
            guard case .matches(let files) = tiles[i].state else { return nil }
            return MovePlanEntry(index: i, files: files)
        }
    }

    func beginMoving(tile index: Int, total: Int) {
        guard tiles.indices.contains(index) else { return }
        tiles[index].state = .moving(done: 0, total: total)
    }

    func setProgress(tile index: Int, done: Int, total: Int) {
        guard tiles.indices.contains(index) else { return }
        tiles[index].state = .moving(done: done, total: total)
    }

    func finishMoving(tile index: Int, moved: Int, failed: Int) {
        guard tiles.indices.contains(index) else { return }
        tiles[index].state = .done(moved: moved, failed: failed)
    }

    func flash(_ index: Int) {
        flashIndex = index
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if self?.flashIndex == index { self?.flashIndex = nil }
        }
    }
}
