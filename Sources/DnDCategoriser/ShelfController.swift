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
        guard !model.isMoving else { return } // previous drop still moving files; ignore this drag
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
        guard !model.isMoving else { return } // panel stays until moves finish
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

    /// Drop anywhere on the panel: every classified file moves to its folder. Refused while classification is
    /// still running or failed, or when nothing matched. Moves run off the main thread; tiles show progress;
    /// the panel hides shortly after the last file lands.
    private func drop(at point: CGPoint) -> Bool {
        guard !model.isMoving else { return false }
        let plan = model.movePlan
        guard model.isReady, !plan.isEmpty else {
            for i in model.tiles.indices { model.flash(i) }
            return false
        }
        hideWork?.cancel()
        model.activeIndex = nil
        for entry in plan { model.beginMoving(tile: entry.index, total: entry.files.count) }

        let jobs = plan.map { (index: $0.index, urls: $0.files.map(\.url), folder: model.tiles[$0.index].folder.path) }
        Task.detached(priority: .userInitiated) { [weak self] in
            var failedNames: [String] = []
            for job in jobs {
                let result = FileMover.move(job.urls, into: job.folder) { done, total in
                    Task { @MainActor [weak self] in self?.model.setProgress(tile: job.index, done: done, total: total) }
                }
                failedNames += result.failed.keys.map(\.lastPathComponent)
                await MainActor.run { [weak self] in
                    self?.model.finishMoving(tile: job.index, moved: result.moved.count, failed: result.failed.count)
                }
            }
            await MainActor.run { [weak self] in self?.movesFinished(failedNames: failedNames.sorted()) }
        }
        return true
    }

    private func movesFinished(failedNames: [String]) {
        if !failedNames.isEmpty { Notifier.moveFailed(failedNames) }
        let work = DispatchWorkItem { [weak self] in
            self?.panel.orderOut(nil)
            self?.model.reset(folders: self?.config.config.folders ?? [], engine: self?.config.config.engine ?? .jev)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
}
