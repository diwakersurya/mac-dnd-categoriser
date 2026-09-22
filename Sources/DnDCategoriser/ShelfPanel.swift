import AppKit
import SwiftUI

/// Flipped container that owns the drag destination. Points handed to callbacks are top-left origin.
final class DropHostView: NSView {
    var onDragMoved: ((CGPoint) -> Void)?
    var onDragExited: (() -> Void)?
    var onDrop: ((CGPoint) -> Bool)?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func point(_ sender: NSDraggingInfo) -> CGPoint {
        convert(sender.draggingLocation, from: nil)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragMoved?(point(sender))
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragMoved?(point(sender))
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDrop?(point(sender)) ?? false
    }
}

final class ShelfPanel: NSPanel {
    let dropView: DropHostView

    init(rootView: some View, layout: TileLayout) {
        dropView = DropHostView(frame: NSRect(x: 0, y: 0, width: layout.panelWidth, height: 200))
        super.init(
            contentRect: dropView.frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        dropView.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: dropView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: dropView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: dropView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: dropView.bottomAnchor),
        ])
        contentView = dropView
    }

    override var canBecomeKey: Bool { true }

    /// Flush with the right edge of the screen under `pointer`, centred on the pointer's Y, clamped to the visible frame.
    func show(near pointer: NSPoint, height: CGFloat) {
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let width = frame.width
        var origin = NSPoint(x: visible.maxX - width - 8, y: pointer.y - height / 2)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - height - 8)
        setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
        orderFrontRegardless()
    }
}
