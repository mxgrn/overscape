import AppKit
import SwiftUI

struct FolderCardView: View {
    let card: FolderCard
    let model: CanvasModel

    @State private var dragStart: CGPoint?
    /// The card frame at the start of a resize.
    @State private var resizeStart: CGRect?
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
            switch card.viewMode {
            case .list:
                columnHeaders
                Divider()
                list
            case .icons:
                grid
            }
        }
        .frame(width: card.width)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    Color.accentColor.opacity(isHovered ? 1 : 0.5),
                    lineWidth: isHovered ? 2.5 : 1.5
                )
        )
        .onHover { hovering in
            isHovered = hovering
            model.setHovered(card.id, hovering)
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .overlay { resizeHandles }
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
        .frame(height: card.contentHeight, alignment: .top)
    }

    /// Icon mode. Icons with an open child card are not highlighted, only the selected icon.
    private var grid: some View {
        let columns = Array(
            repeating: GridItem(.fixed(CardLayout.iconCellWidth(width: card.width)), spacing: 0),
            count: card.iconColumns
        )
        return ScrollView {
            Group {
                if card.entries.isEmpty {
                    Text("Empty folder")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: CardLayout.iconCellHeight)
                } else {
                    LazyVGrid(columns: columns, spacing: 0) {
                        ForEach(card.entries) { entry in
                            iconCell(entry)
                        }
                    }
                }
            }
            .padding(CardLayout.gridPadding)
            // The connector lines start at an icon, so the model must know the scroll position.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(Self.listSpace)).minY
            } action: { offset in
                model.setScrollOffset(card.id, offset)
            }
        }
        .coordinateSpace(.named(Self.listSpace))
        .frame(height: card.contentHeight, alignment: .top)
    }

    private func iconCell(_ entry: FileEntry) -> some View {
        let isSelected = selection == entry.id
        return VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                .resizable()
                .frame(width: CardLayout.iconSize, height: CardLayout.iconSize)
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? Color.primary.opacity(0.1) : .clear)
                )
            Text(entry.name)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.accentColor : .clear)
                )
        }
        .padding(.top, 4)
        .frame(width: CardLayout.iconCellWidth(width: card.width), height: CardLayout.iconCellHeight, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { selection = entry.id }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            guard entry.isDirectory else { return }
            model.openChild(of: card.id, folder: entry.url)
        })
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

    // MARK: - Resizing

    /// The 4 edges first, then the 4 corners, so that the corners are on top.
    private static let handleEdges: [CardEdges] = [
        .left, .right, .top, .bottom,
        [.top, .left], [.top, .right], [.bottom, .left], [.bottom, .right],
    ]

    private var resizeHandles: some View {
        ZStack {
            ForEach(Self.handleEdges, id: \.rawValue) { edges in
                resizeHandle(edges)
            }
        }
    }

    /// A handle is half inside and half outside the card.
    private func resizeHandle(_ edges: CardEdges) -> some View {
        let onX = !edges.isDisjoint(with: [.left, .right])
        let onY = !edges.isDisjoint(with: [.top, .bottom])
        let size = onX && onY ? CardLayout.resizeCornerSize : CardLayout.resizeEdgeThickness
        let alignment = Alignment(
            horizontal: edges.contains(.left) ? .leading : edges.contains(.right) ? .trailing : .center,
            vertical: edges.contains(.top) ? .top : edges.contains(.bottom) ? .bottom : .center
        )
        return ResizeHandle(edges: edges) { translation in
            let start = resizeStart ?? card.frame
            if resizeStart == nil {
                resizeStart = start
                model.bringToFront(card.id)
            }
            // The translation is in screen points. Divide by the zoom to get canvas points.
            model.resize(card.id, edges: edges, from: start, by: CGSize(
                width: translation.width / model.zoom,
                height: translation.height / model.zoom
            ))
        } onEnded: {
            resizeStart = nil
        }
        .frame(width: onX ? size : nil, height: onY ? size : nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .offset(
            x: edges.contains(.left) ? -size / 2 : edges.contains(.right) ? size / 2 : 0,
            y: edges.contains(.top) ? -size / 2 : edges.contains(.bottom) ? size / 2 : 0
        )
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

/// An invisible area on an edge or a corner of a card. A drag on it resizes the card.
/// It shows a resize cursor while the mouse is on it and during the drag.
private struct ResizeHandle: View {
    let edges: CardEdges
    let onChanged: (CGSize) -> Void
    let onEnded: () -> Void

    @State private var isHovered = false
    @State private var isDragging = false
    @State private var isCursorPushed = false

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                updateCursor()
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        isDragging = true
                        updateCursor()
                        onChanged(value.translation)
                    }
                    .onEnded { _ in
                        isDragging = false
                        updateCursor()
                        onEnded()
                    }
            )
            .onDisappear {
                if isCursorPushed { NSCursor.pop() }
                isCursorPushed = false
            }
    }

    private func updateCursor() {
        let wanted = isHovered || isDragging
        if wanted, !isCursorPushed {
            cursor.push()
            isCursorPushed = true
        } else if !wanted, isCursorPushed {
            NSCursor.pop()
            isCursorPushed = false
        }
    }

    private var cursor: NSCursor {
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition = switch edges {
            case .left: .left
            case .right: .right
            case .top: .top
            case .bottom: .bottom
            case [.top, .left]: .topLeft
            case [.top, .right]: .topRight
            case [.bottom, .left]: .bottomLeft
            default: .bottomRight
            }
            return .frameResize(position: position, directions: .all)
        }
        // macOS 14 has no public cursor for a diagonal resize.
        if edges == .left || edges == .right { return .resizeLeftRight }
        if edges == .top || edges == .bottom { return .resizeUpDown }
        return .crosshair
    }
}
