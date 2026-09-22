import AppKit
import Combine

/// Glue: DragWatcher → ShelfPanel → Classifier → FileMover.
@MainActor
final class ShelfController {
    let config: ConfigStore
    let model = ShelfViewModel()
    let layout = TileLayout()
    let watcher = DragWatcher()

    private let panel: ShelfPanel
    private var files: [FileInfo] = []
    private var classifyTask: Task<Void, Never>?
    private var hideWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init(config: ConfigStore) {
        self.config = config
        panel = ShelfPanel(rootView: ShelfView(model: model, layout: layout), layout: layout)
        model.reset(folders: config.config.folders, engine: config.config.engine)

        // Folder list or engine changed in Settings or via "+": rebuild tiles.
        // If a drag is in flight its results are dropped; the next drag re-classifies.
        config.$config
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] cfg in
                guard let self else { return }
                self.model.reset(folders: cfg.folders, engine: cfg.engine)
                if self.panel.isVisible {
                    self.panel.show(near: NSEvent.mouseLocation, height: self.panelHeight)
                }
            }
            .store(in: &cancellables)

        panel.dropView.onDragMoved = { [weak self] point in self?.pointerMoved(point) }
        panel.dropView.onDragExited = { [weak self] in self?.model.activeIndex = nil }
        panel.dropView.onDrop = { [weak self] point in self?.drop(at: point) ?? false }

        watcher.onDragStarted = { [weak self] urls in self?.dragStarted(urls) }
        watcher.onDragEnded = { [weak self] in self?.dragEnded() }
        watcher.start()
    }

    private var panelHeight: CGFloat { layout.panelHeight(tileCount: model.slotCount) }

    private func makeClassifier() -> Classifier {
        switch config.config.engine {
        case .jev: return JevClassifier(apiKey: { KeychainStore.read() })
        case .onDevice: return OnDeviceClassifier()
        }
    }

    private func dragStarted(_ urls: [URL]) {
        hideWork?.cancel()
        classifyTask?.cancel()

        files = urls.enumerated().map { FileInfo(id: "f\($0.offset)", url: $0.element) }
        model.reset(folders: config.config.folders, engine: config.config.engine)
        model.beginSession()
        panel.show(near: NSEvent.mouseLocation, height: panelHeight)

        let classifier = makeClassifier()
        let folders = model.activeFolders
        let snapshot = files
        classifyTask = Task { [weak self] in
            do {
                let result = try await classifier.classify(files: snapshot, folders: folders)
                guard !Task.isCancelled else { return }
                self?.model.apply(results: result, files: snapshot)
            } catch let error as ClassifierError {
                guard !Task.isCancelled else { return }
                self?.model.fail(error.message)
            } catch {
                guard !Task.isCancelled else { return }
                self?.model.fail(error.localizedDescription)
            }
        }
    }

    private func dragEnded() {
        let work = DispatchWorkItem { [weak self] in
            self?.panel.orderOut(nil)
            self?.model.activeIndex = nil
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Over the flyout column the current slot stays active, so reading the file list does not drop the highlight.
    private func slot(at point: CGPoint) -> Int? {
        if point.x < layout.shelfX, let current = model.activeIndex { return current }
        return layout.tileIndex(at: point, tileCount: model.slotCount)
    }

    private func pointerMoved(_ point: CGPoint) {
        model.activeIndex = slot(at: point)
    }

    /// Moves only the files classified for the tile under the pointer. Refuses if not ready, no matches, or "No folder" slot.
    private func drop(at point: CGPoint) -> Bool {
        guard let index = slot(at: point) else { return false }
        guard index < model.tiles.count, let matched = model.matchedFiles(at: index) else {
            model.flash(index)
            return false
        }
        let folder = model.tiles[index].folder
        let result = FileMover.move(matched.map(\.url), into: folder.path)
        if !result.failed.isEmpty {
            Notifier.moveFailed(result.failed.keys.map(\.lastPathComponent).sorted())
        }
        hideWork?.cancel()
        panel.orderOut(nil)
        model.activeIndex = nil
        return !result.moved.isEmpty
    }
}
