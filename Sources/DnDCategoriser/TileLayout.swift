import CoreGraphics

/// Two columns: a flyout column on the left (file names for the hovered tile) and the shelf column on the right
/// (fixed-height tiles). All coordinates are top-left origin.
struct TileLayout: Equatable {
    var flyoutWidth: CGFloat = 240
    var gap: CGFloat = 8
    var panelWidth: CGFloat = 260   // shelf column width
    var tileHeight: CGFloat = 72
    var spacing: CGFloat = 8
    var padding: CGFloat = 12
    var margin: CGFloat = 24        // vicinity outset around each tile
    var flyoutHeaderHeight: CGFloat = 30
    var flyoutRowHeight: CGFloat = 20
    var flyoutMaxRows: Int = 10

    var shelfX: CGFloat { flyoutWidth + gap }
    var totalWidth: CGFloat { shelfX + panelWidth }

    func panelHeight(tileCount: Int) -> CGFloat {
        guard tileCount > 0 else { return padding * 2 }
        return padding * 2 + CGFloat(tileCount) * tileHeight + CGFloat(tileCount - 1) * spacing
    }

    func frame(at index: Int) -> CGRect {
        CGRect(
            x: shelfX + padding,
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

    /// Flyout for slot `index`: top-aligned with the tile, shifted up (and capped) so it stays inside the panel.
    func flyoutFrame(forSlot index: Int, slotCount: Int, rowCount: Int) -> CGRect {
        let rows = min(max(rowCount, 1), flyoutMaxRows)
        let panelH = panelHeight(tileCount: slotCount)
        let height = min(flyoutHeaderHeight + CGFloat(rows) * flyoutRowHeight + padding, panelH - 2 * padding)
        let y = min(frame(at: index).minY, max(padding, panelH - height - padding))
        return CGRect(x: 0, y: y, width: flyoutWidth, height: height)
    }
}
