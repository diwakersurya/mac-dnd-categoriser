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
        dropView = DropHostView(frame: NSRect(x: 0, y: 0, width: layout.totalWidth, height: 200))
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

    private var generation = 0

    /// Shelf column flush with the right edge of the screen under `pointer`, centred on the pointer's Y, clamped to the
    /// visible frame. First appearance fades and slides in from the edge; while visible it just re-positions.
    func show(near pointer: NSPoint, height: CGFloat) {
        generation += 1
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let width = frame.width
        var origin = NSPoint(x: visible.maxX - width - 8, y: pointer.y - height / 2)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - height - 8)
        let target = NSRect(origin: origin, size: NSSize(width: width, height: height))

        if isVisible && alphaValue > 0.99 {
            setFrame(target, display: true)
            orderFrontRegardless()
            return
        }
        // Cancel any in-flight fade-out, then animate in.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            animator().alphaValue = 0
        }
        setFrame(target.offsetBy(dx: 24, dy: 0), display: false)
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(target, display: true)
        }
    }

    /// Fades out over `duration`, then orders out and calls `completion`. A `show` during the fade cancels it.
    func dismiss(duration: TimeInterval, completion: (() -> Void)? = nil) {
        generation += 1
        let mine = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.generation == mine else { return }
            self.orderOut(nil)
            self.alphaValue = 1
            completion?()
        })
    }
}
