import AppKit
import Combine

/// Glue: DragWatcher → ShelfPanel → Classifier → FileMover.
@MainActor
final class ShelfController {
    let config: ConfigStore
    let session: SessionLog
    let model = ShelfViewModel()
    let layout = TileLayout()
    let watcher = DragWatcher()

    private let panel: ShelfPanel
    private var files: [FileInfo] = []
    private var classifyTask: Task<Void, Never>?
    private var hideWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init(config: ConfigStore, session: SessionLog) {
        self.config = config
        self.session = session
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
        let template = config.config.payload
        switch config.config.engine {
        case .jev: return JevClassifier(apiKey: { KeychainStore.read() }, template: template)
        case .onDevice: return OnDeviceClassifier(template: template)
        }
    }

    private func dragStarted(_ urls: [URL]) {
        guard !model.isMoving else { return } // previous drop still moving files; ignore this drag
        hideWork?.cancel()
        classifyTask?.cancel()

        files = urls.enumerated().map { FileInfo(id: "f\($0.offset)", url: $0.element) }
        session.lastFiles = files
        model.reset(folders: config.config.folders, engine: config.config.engine)
        model.beginSession()
        panel.show(near: NSEvent.mouseLocation, height: panelHeight)

        let classifier = makeClassifier()
        let folders = model.activeFolders
        let snapshot = files
        let engine = config.config.engine
        let requestText = config.config.logRequests
            ? PayloadPreview.render(engine: engine, files: snapshot, folders: folders, template: config.config.payload)
            : nil
        let started = Date()
        classifyTask = Task { [weak self] in
            var responseText: String
            do {
                let result = try await classifier.classify(files: snapshot, folders: folders)
                guard !Task.isCancelled else { return }
                self?.model.apply(results: result, files: snapshot)
                responseText = result.isEmpty ? "(no file matched any folder)" : result.sorted { $0.key < $1.key }.map { "\($0.key) → \($0.value)" }.joined(separator: "\n")
            } catch let error as ClassifierError {
                guard !Task.isCancelled else { return }
                self?.model.fail(error.message)
                responseText = "ERROR: \(error.message)"
            } catch {
                guard !Task.isCancelled else { return }
                self?.model.fail(error.localizedDescription)
                responseText = "ERROR: \(error.localizedDescription)"
            }
            if let requestText {
                self?.session.record(RequestLogEntry(date: started, engine: engine, latency: Date().timeIntervalSince(started), request: requestText, response: responseText))
            }
        }
    }

    private func dragEnded() {
        guard !model.isMoving else { return } // panel stays until moves finish
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.panel.dismiss(duration: 0.4) { [weak self] in self?.model.activeIndex = nil }
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
                let total = job.urls.count
                // Same-volume moves are instant renames; pace the bar so each tile visibly fills (>= ~0.6 s per tile).
                let stepNanos = UInt64(max(0.08, 0.6 / Double(total)) * 1_000_000_000)
                var moved = 0
                var failed = 0
                for (i, url) in job.urls.enumerated() {
                    let result = FileMover.move([url], into: job.folder)
                    moved += result.moved.count
                    failed += result.failed.count
                    failedNames += result.failed.keys.map(\.lastPathComponent)
                    try? await Task.sleep(nanoseconds: stepNanos)
                    let done = i + 1
                    await MainActor.run { [weak self] in self?.model.setProgress(tile: job.index, done: done, total: total) }
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
                let m = moved, f = failed
                await MainActor.run { [weak self] in self?.model.finishMoving(tile: job.index, moved: m, failed: f) }
            }
            let failedSorted = failedNames.sorted()
            await MainActor.run { [weak self] in self?.movesFinished(failedNames: failedSorted) }
        }
        return true
    }

    /// Hold the "Moved n" results for 2 s, then fade the panel out over 1 s.
    private func movesFinished(failedNames: [String]) {
        if !failedNames.isEmpty { Notifier.moveFailed(failedNames) }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.panel.dismiss(duration: 1.0) { [weak self] in
                guard let self else { return }
                self.model.reset(folders: self.config.config.folders, engine: self.config.config.engine)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }
}
