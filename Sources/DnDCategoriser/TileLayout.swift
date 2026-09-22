import CoreGraphics

enum ShelfEdge: String, Codable, CaseIterable, Identifiable {
    case top, right, bottom, left
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Geometry of the shelf panel for a given screen edge. All coordinates are top-left origin within the panel.
///
/// Vertical edges (left/right): tiles stack vertically in a shelf column; the flyout column sits beside it, away from the edge.
/// Horizontal edges (top/bottom): tiles form a row; the flyout region sits below (top edge) or above (bottom edge) the row.
struct TileLayout: Equatable {
    var edge: ShelfEdge = .right
    var flyoutWidth: CGFloat = 240
    var gap: CGFloat = 8
    var tileHeight: CGFloat = 72
    var verticalTileWidth: CGFloat = 236
    var horizontalTileWidth: CGFloat = 200
    var spacing: CGFloat = 8
    var padding: CGFloat = 12
    var margin: CGFloat = 24        // vicinity outset around each tile
    var flyoutHeaderHeight: CGFloat = 30
    var flyoutRowHeight: CGFloat = 20
    var flyoutMaxRows: Int = 10

    var isVertical: Bool { edge == .left || edge == .right }
    var tileWidth: CGFloat { isVertical ? verticalTileWidth : horizontalTileWidth }
    /// Shelf extent perpendicular to the screen edge.
    var shelfThickness: CGFloat { isVertical ? verticalTileWidth + 2 * padding : tileHeight + 2 * padding }
    var flyoutMaxHeight: CGFloat { flyoutHeaderHeight + CGFloat(flyoutMaxRows) * flyoutRowHeight + padding }
    /// Direction the panel slides in from (points, AppKit axes: +y is up).
    var slideOffset: CGVector {
        switch edge {
        case .right: return CGVector(dx: 24, dy: 0)
        case .left: return CGVector(dx: -24, dy: 0)
        case .top: return CGVector(dx: 0, dy: 24)
        case .bottom: return CGVector(dx: 0, dy: -24)
        }
    }

    /// Shelf extent along the screen edge for `slotCount` tiles.
    func shelfLength(slotCount: Int) -> CGFloat {
        guard slotCount > 0 else { return padding * 2 }
        let along = isVertical ? tileHeight : tileWidth
        return padding * 2 + CGFloat(slotCount) * along + CGFloat(slotCount - 1) * spacing
    }

    func panelSize(slotCount: Int) -> CGSize {
        let length = shelfLength(slotCount: slotCount)
        if isVertical {
            return CGSize(width: flyoutWidth + gap + shelfThickness, height: length)
        }
        return CGSize(width: max(length, flyoutWidth), height: shelfThickness + gap + flyoutMaxHeight)
    }

    func shelfFrame(slotCount: Int) -> CGRect {
        let length = shelfLength(slotCount: slotCount)
        switch edge {
        case .right: return CGRect(x: flyoutWidth + gap, y: 0, width: shelfThickness, height: length)
        case .left: return CGRect(x: 0, y: 0, width: shelfThickness, height: length)
        case .top: return CGRect(x: 0, y: 0, width: length, height: shelfThickness)
        case .bottom: return CGRect(x: 0, y: flyoutMaxHeight + gap, width: length, height: shelfThickness)
        }
    }

    func frame(at index: Int) -> CGRect {
        let shelf = shelfFrame(slotCount: 0) // origin does not depend on count
        if isVertical {
            return CGRect(x: shelf.minX + padding, y: padding + CGFloat(index) * (tileHeight + spacing), width: tileWidth, height: tileHeight)
        }
        return CGRect(x: padding + CGFloat(index) * (tileWidth + spacing), y: shelf.minY + padding, width: tileWidth, height: tileHeight)
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

    /// Flyout for slot `index`, aligned with the tile and kept inside the panel.
    func flyoutFrame(forSlot index: Int, slotCount: Int, rowCount: Int) -> CGRect {
        let rows = min(max(rowCount, 1), flyoutMaxRows)
        let raw = flyoutHeaderHeight + CGFloat(rows) * flyoutRowHeight + padding
        let tile = frame(at: index)
        let panel = panelSize(slotCount: slotCount)
        if isVertical {
            let height = min(raw, panel.height - 2 * padding)
            let y = min(tile.minY, max(padding, panel.height - height - padding))
            let x: CGFloat = edge == .right ? 0 : shelfThickness + gap
            return CGRect(x: x, y: y, width: flyoutWidth, height: height)
        }
        let height = min(raw, flyoutMaxHeight)
        let x = min(tile.minX, max(0, panel.width - flyoutWidth))
        let y: CGFloat = edge == .top ? shelfThickness + gap : flyoutMaxHeight - height
        return CGRect(x: x, y: y, width: flyoutWidth, height: height)
    }

    /// True when `point` is on the flyout side of the shelf (whether or not a flyout is showing).
    func isOverFlyout(_ point: CGPoint, slotCount: Int) -> Bool {
        let shelf = shelfFrame(slotCount: slotCount)
        switch edge {
        case .right: return point.x < shelf.minX
        case .left: return point.x > shelf.maxX
        case .top: return point.y > shelf.maxY
        case .bottom: return point.y < shelf.minY
        }
    }
}
