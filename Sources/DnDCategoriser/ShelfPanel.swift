import AppKit
import SwiftUI

/// Flipped container that owns the drag destination. Points handed to callbacks are top-left origin.
final class DropHostView: NSView {
    /// Returns whether a drop at this point would be accepted; drives the cursor's drop indicator.
    var onDragMoved: ((CGPoint) -> Bool)?
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
        (onDragMoved?(point(sender)) ?? false) ? .move : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        (onDragMoved?(point(sender)) ?? false) ? .move : []
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

    init(rootView: some View) {
        dropView = DropHostView(frame: NSRect(x: 0, y: 0, width: 508, height: 200))
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

    /// Shelf flush with the configured screen edge, centred on the pointer along that edge, clamped to the visible
    /// frame. First appearance fades and slides in from the edge; while visible it just re-positions.
    func show(near pointer: NSPoint, layout: TileLayout, slotCount: Int) {
        generation += 1
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = layout.panelSize(slotCount: slotCount)
        var origin: NSPoint
        switch layout.edge {
        case .right: origin = NSPoint(x: visible.maxX - size.width - 8, y: pointer.y - size.height / 2)
        case .left: origin = NSPoint(x: visible.minX + 8, y: pointer.y - size.height / 2)
        case .top: origin = NSPoint(x: pointer.x - size.width / 2, y: visible.maxY - size.height - 8)
        case .bottom: origin = NSPoint(x: pointer.x - size.width / 2, y: visible.minY + 8)
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        let target = NSRect(origin: origin, size: NSSize(width: size.width, height: size.height))

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
        setFrame(target.offsetBy(dx: layout.slideOffset.dx, dy: layout.slideOffset.dy), display: false)
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
