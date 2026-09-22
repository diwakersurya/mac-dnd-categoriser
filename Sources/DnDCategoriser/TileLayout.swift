import CoreGraphics

/// Fixed vertical stack of equal-height tiles. All coordinates are top-left origin.
struct TileLayout: Equatable {
    var panelWidth: CGFloat = 260
    var tileHeight: CGFloat = 96
    var spacing: CGFloat = 8
    var padding: CGFloat = 12
    var margin: CGFloat = 24 // vicinity outset around each tile

    func panelHeight(tileCount: Int) -> CGFloat {
        guard tileCount > 0 else { return padding * 2 }
        return padding * 2 + CGFloat(tileCount) * tileHeight + CGFloat(tileCount - 1) * spacing
    }

    func frame(at index: Int) -> CGRect {
        CGRect(
            x: padding,
            y: padding + CGFloat(index) * (tileHeight + spacing),
            width: panelWidth - 2 * padding,
            height: tileHeight
        )
    }

    /// Index of the tile whose margin-outset frame contains `point`; nearest centre wins on overlap.
    func tileIndex(at point: CGPoint, tileCount: Int) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for i in 0..<max(0, tileCount) {
            let f = frame(at: i)
            guard f.insetBy(dx: -margin, dy: -margin).contains(point) else { continue }
            let d = hypot(point.x - f.midX, point.y - f.midY)
            if best == nil || d < best!.distance { best = (i, d) }
        }
        return best?.index
    }
}
