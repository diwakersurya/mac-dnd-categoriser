import AppKit

/// Detects system-wide file drags by watching the drag pasteboard while the left button is dragged.
final class DragWatcher {
    var onDragStarted: (([URL]) -> Void)?
    var onDragEnded: (() -> Void)?

    private let pasteboard = NSPasteboard(name: .drag)
    private var lastChangeCount: Int
    private var monitor: Any?
    private var endTimer: Timer?
    private(set) var sessionActive = false

    init() {
        lastChangeCount = pasteboard.changeCount
    }

    deinit { stop() }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            self?.checkForNewDrag()
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        endTimer?.invalidate()
        endTimer = nil
    }

    static func fileURLs(from pb: NSPasteboard) -> [URL] {
        (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    private func checkForNewDrag() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        let urls = Self.fileURLs(from: pasteboard)
        guard !urls.isEmpty else { return }
        sessionActive = true
        onDragStarted?(urls)
        startEndTimer()
    }

    private func startEndTimer() {
        endTimer?.invalidate()
        endTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if NSEvent.pressedMouseButtons & 1 == 0 {
                timer.invalidate()
                self.endTimer = nil
                self.sessionActive = false
                self.onDragEnded?()
            }
        }
    }
}
