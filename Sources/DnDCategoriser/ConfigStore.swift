import Foundation
import Combine

final class ConfigStore: ObservableObject {
    @Published var config: Config {
        didSet { if config != oldValue { save() } }
    }
    let url: URL

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DnDCategoriser/config.json")
    }

    init(url: URL = ConfigStore.defaultURL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode(Config.self, from: data) {
            config = loaded
        } else {
            config = Config()
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: url, options: .atomic)
        } catch {
            NSLog("DnDCategoriser: config save failed: \(error)")
        }
    }

    @discardableResult
    func addFolder(path: URL, description: String) -> Folder {
        let name = path.lastPathComponent
        let id = Slug.make(from: name, existing: Set(config.folders.map(\.id)))
        let folder = Folder(id: id, path: path, name: name, description: description)
        config.folders.append(folder)
        return folder
    }

    func removeFolder(id: String) {
        config.folders.removeAll { $0.id == id }
    }
}
