import AppKit
import SwiftUI

struct FolderCardView: View {
    let card: FolderCard
    let model: CanvasModel

    @State private var dragStart: CGPoint?
    @State private var selection: FileEntry.ID?
    /// True while the mouse is on the card. The card then shows a stronger border.
    @State private var isHovered = false

    private static let sizeColumn: CGFloat = 70
    private static let dateColumn: CGFloat = 120
    nonisolated private static let listSpace = "cardList"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            columnHeaders
            Divider()
            list
        }
        .frame(width: CardLayout.width)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    Color.accentColor.opacity(isHovered ? 1 : 0.5),
                    lineWidth: isHovered ? 2.5 : 1.5
                )
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .offset(x: card.position.x, y: card.position.y)
    }

    // MARK: - Parts

    private var header: some View {
        ZStack {
            HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: card.url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(card.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            HStack {
                Button {
                    model.close(card.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close card")
                Spacer()
                Text("\(card.entries.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
        }
        .frame(height: CardLayout.headerHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(moveGesture)
    }

    private var columnHeaders: some View {
        HStack(spacing: 8) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Size").frame(width: Self.sizeColumn, alignment: .trailing)
            Text("Date Modified").frame(width: Self.dateColumn, alignment: .leading)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: CardLayout.columnHeaderHeight)
    }

    private var list: some View {
        let openChildren = Set(model.cards.filter { $0.parentID == card.id }.map(\.url))
        return ScrollView {
            LazyVStack(spacing: 0) {
                if card.entries.isEmpty {
                    Text("Empty folder")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(height: CardLayout.rowHeight)
                }
                ForEach(Array(card.entries.enumerated()), id: \.element.id) { index, entry in
                    row(entry, index: index, isOpen: openChildren.contains(entry.url))
                }
            }
            // The connector lines start at a row, so the model must know the scroll position.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(Self.listSpace)).minY
            } action: { offset in
                model.setScrollOffset(card.id, offset)
            }
        }
        .coordinateSpace(.named(Self.listSpace))
        .frame(height: CardLayout.listHeight(entryCount: card.entries.count))
    }

    private func row(_ entry: FileEntry, index: Int, isOpen: Bool) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(entry.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(Self.format(size: entry.size))
                .foregroundStyle(.secondary)
                .frame(width: Self.sizeColumn, alignment: .trailing)

            Text(entry.modified.map(Self.format(date:)) ?? "--")
                .foregroundStyle(.secondary)
                .frame(width: Self.dateColumn, alignment: .leading)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(height: CardLayout.rowHeight)
        .background(rowBackground(isHighlighted: isOpen || selection == entry.id, index: index))
        .contentShape(Rectangle())
        .onTapGesture { selection = entry.id }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            guard entry.isDirectory else { return }
            model.openChild(of: card.id, folder: entry.url)
        })
    }

    private func rowBackground(isHighlighted: Bool, index: Int) -> Color {
        if isHighlighted { return Color.accentColor.opacity(0.2) }
        return index.isMultiple(of: 2) ? .clear : Color.primary.opacity(0.035)
    }

    // MARK: - Dragging

    /// Moves the card in the model while the drag continues, so that the connector lines follow it.
    private var moveGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                let start = dragStart ?? card.position
                if dragStart == nil {
                    dragStart = start
                    model.bringToFront(card.id)
                }
                // The translation is in screen points. Divide by the zoom to get canvas points.
                model.move(card.id, to: CGPoint(
                    x: start.x + value.translation.width / model.zoom,
                    y: start.y + value.translation.height / model.zoom
                ))
            }
            .onEnded { _ in dragStart = nil }
    }

    // MARK: - Formatting

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy, HH:mm"
        return formatter
    }()

    static func format(date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func format(size: Int64?) -> String {
        guard let size else { return "--" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
