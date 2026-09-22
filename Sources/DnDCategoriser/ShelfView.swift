import SwiftUI

struct ShelfView: View {
    @ObservedObject var model: ShelfViewModel
    let layout: TileLayout

    var body: some View {
        VStack(spacing: layout.spacing) {
            ForEach(Array(model.tiles.enumerated()), id: \.element.id) { index, tile in
                TileView(tile: tile, active: model.activeIndex == index, flashing: model.flashIndex == index)
                    .frame(height: layout.tileHeight)
            }
            AddTileView(active: model.activeIndex == model.tiles.count) { model.onAddFolder?() }
                .frame(height: layout.tileHeight)
        }
        .padding(layout.padding)
        .frame(width: layout.panelWidth)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .topTrailing) {
            Text(model.engineLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.trailing, layout.padding + 4)
                .padding(.top, 2)
        }
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
            if !tile.folder.description.isEmpty {
                Text(tile.folder.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(active ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(flashing ? Color.red : (active ? Color.accentColor : Color.clear), lineWidth: 2)
        )
        .opacity(dimmed ? 0.45 : 1)
        .animation(.easeOut(duration: 0.12), value: active)
        .animation(.easeOut(duration: 0.12), value: flashing)
    }

    private var dimmed: Bool {
        if case .empty = tile.state { return true }
        return false
    }

    @ViewBuilder private var trailing: some View {
        switch tile.state {
        case .pending: ProgressView().controlSize(.small)
        case .matches(let files): Text("\(files.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        default: EmptyView()
        }
    }

    @ViewBuilder private var content: some View {
        switch tile.state {
        case .matches(let files):
            if active {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(files) { Text($0.displayName).font(.caption).lineLimit(1) }
                    }
                }
            } else {
                ForEach(files.prefix(2)) { Text($0.displayName).font(.caption).lineLimit(1) }
                if files.count > 2 {
                    Text("+\(files.count - 2) more").font(.caption2).foregroundStyle(.secondary)
                }
            }
        case .empty:
            Text("No matching files").font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
        case .pending:
            Text("Classifying…").font(.caption).foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }
}

struct AddTileView: View {
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "plus.circle").font(.title2)
                Text("Add folder").font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(active ? Color.accentColor : Color.secondary.opacity(0.5))
        )
    }
}
