import SwiftUI
import AppKit

struct ShelfView: View {
    @ObservedObject var model: ShelfViewModel

    var body: some View {
        let layout = model.layout
        let size = layout.panelSize(slotCount: model.slotCount)
        let shelf = layout.shelfFrame(slotCount: model.slotCount)
        ZStack(alignment: .topLeading) {
            shelfBody(layout)
                .frame(width: shelf.width, height: shelf.height)
                .offset(x: shelf.minX, y: shelf.minY)

            if let index = model.activeIndex, let content = model.flyout(forSlot: index) {
                let f = layout.flyoutFrame(forSlot: index, slotCount: model.slotCount, rowCount: content.files.count)
                FlyoutView(content: content, layout: layout)
                    .frame(width: f.width, height: f.height)
                    .offset(x: f.minX, y: f.minY)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.12), value: model.activeIndex)
    }

    @ViewBuilder
    private func shelfBody(_ layout: TileLayout) -> some View {
        let tiles = tileViews(layout)
        Group {
            if layout.isVertical {
                VStack(spacing: layout.spacing) { tiles }
            } else {
                HStack(spacing: layout.spacing) { tiles }
            }
        }
        .padding(layout.padding)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .topTrailing) {
            Text(model.engineLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.trailing, layout.padding + 4)
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func tileViews(_ layout: TileLayout) -> some View {
        ForEach(Array(model.tiles.enumerated()), id: \.element.id) { index, tile in
            TileView(tile: tile, active: model.activeIndex == index, flashing: model.flashIndex == index)
                .frame(width: layout.tileWidth, height: layout.tileHeight)
        }
        if let slot = model.unmatchedSlot {
            UnmatchedTileView(count: model.unmatched.count, active: model.activeIndex == slot, flashing: model.flashIndex == slot)
                .frame(width: layout.tileWidth, height: layout.tileHeight)
        }
    }
}

struct CountBadge: View {
    let count: Int
    var muted = false

    var body: some View {
        Text("\(count)")
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(muted ? Color.primary : Color.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(muted ? Color.secondary.opacity(0.3) : Color.accentColor))
    }
}

struct TileView: View {
    let tile: Tile
    let active: Bool
    let flashing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: tile.missing ? "folder.badge.questionmark" : "folder.fill")
                Text(tile.folder.name).font(.headline).lineLimit(1)
                Spacer()
                trailing
            }
            subtitle
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(active ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: active || flashing ? 2 : 1.5)
        )
        .opacity(dimmed ? 0.45 : 1)
        .animation(.easeOut(duration: 0.12), value: active)
        .animation(.easeOut(duration: 0.12), value: flashing)
    }

    private var hasMatches: Bool {
        switch tile.state {
        case .matches, .moving, .done: return true
        default: return false
        }
    }

    private var dimmed: Bool {
        if case .empty = tile.state { return true }
        return false
    }

    private var borderColor: Color {
        if flashing { return .red }
        if active || hasMatches { return .accentColor }
        return .clear
    }

    @ViewBuilder private var trailing: some View {
        switch tile.state {
        case .pending: ProgressView().controlSize(.small)
        case .matches(let files): CountBadge(count: files.count)
        case .moving(_, let total): CountBadge(count: total)
        case .done(_, let failed):
            Image(systemName: failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(failed == 0 ? Color.green : Color.orange)
        default: EmptyView()
        }
    }

    @ViewBuilder private var subtitle: some View {
        switch tile.state {
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
        case .empty:
            Text("No matching files").font(.caption).foregroundStyle(.secondary)
        case .pending:
            Text("Classifying…").font(.caption).foregroundStyle(.secondary)
        case .moving(let done, let total):
            VStack(alignment: .leading, spacing: 3) {
                Text("Moving \(min(done + 1, total)) of \(total)…").font(.caption).foregroundStyle(.secondary)
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .animation(.linear(duration: 0.15), value: done)
            }
        case .done(let moved, let failed):
            Text(failed == 0 ? "Moved \(moved)" : "Moved \(moved), \(failed) failed")
                .font(.caption)
                .foregroundStyle(failed == 0 ? Color.secondary : Color.orange)
        case .matches, .idle:
            Text(tile.folder.description.isEmpty ? " " : tile.folder.description)
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

/// Trailing slot for dragged files that matched no folder. Not a drop target.
struct UnmatchedTileView: View {
    let count: Int
    let active: Bool
    let flashing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "tray")
                Text(ShelfViewModel.unmatchedTitle).font(.headline)
                Spacer()
                CountBadge(count: count, muted: true)
            }
            Text("These stay where they are").font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(active ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(flashing ? Color.red : Color.clear, lineWidth: 2))
        .opacity(0.7)
    }
}

struct FlyoutView: View {
    let content: FlyoutContent
    let layout: TileLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.right.circle.fill").foregroundStyle(Color.accentColor)
                Text(content.title).font(.headline).lineLimit(1)
                Spacer()
                Text(content.files.count == 1 ? "1 file" : "\(content.files.count) files")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(height: layout.flyoutHeaderHeight)
            Divider()
            ScrollView(.vertical, showsIndicators: content.files.count > layout.flyoutMaxRows) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(content.files) { file in
                        HStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                                .resizable()
                                .frame(width: 14, height: 14)
                            Text(file.displayName).font(.caption).lineLimit(1).truncationMode(.middle)
                        }
                        .frame(height: layout.flyoutRowHeight)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.5), lineWidth: 1))
    }
}
