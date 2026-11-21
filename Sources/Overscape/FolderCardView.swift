import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FolderCardView: View {
    let card: FolderCard
    let model: CanvasModel

    @State private var dragStart: CGPoint?
    /// The card frame at the start of a resize.
    @State private var resizeStart: CGRect?
    /// True while the mouse is on the card. The card then shows a stronger border.
    @State private var isHovered = false
    /// True while dragged files are on the card. The card then shows a stronger border.
    @State private var isDropTargeted = false

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
                    Color.accentColor.opacity(isHovered || isDropTargeted ? 1 : 0.5),
                    lineWidth: isHovered || isDropTargeted ? 2.5 : 1.5
                )
        )
        .onHover { hovering in
            isHovered = hovering
            model.setHovered(card.id, hovering)
        }
        .animation(.easeOut(duration: 0.12), value: isHovered || isDropTargeted)
        .onDrop(of: [.fileURL], delegate: CardDropDelegate(cardID: card.id, model: model, isTargeted: $isDropTargeted))
        // Show the changes that other apps make in the folder.
        .task(id: card.url) {
            for await _ in FolderWatcher.changes(in: card.url) {
                model.reload()
            }
        }
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
                    // Drag the icon to the sidebar to make the folder a favorite.
                    .onDrag { NSItemProvider(object: card.url as NSURL) }
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

    /// List mode. Rows with an open child card are not highlighted, only the selected row.
    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if card.entries.isEmpty {
                    Text("Empty folder")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(height: CardLayout.rowHeight)
                }
                ForEach(Array(card.entries.enumerated()), id: \.element.id) { index, entry in
                    row(entry, index: index)
                }
            }
            // The connector lines start at a row, so the model must know the scroll position.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(Self.listSpace)).minY
            } action: { offset in
                model.setScrollOffset(card.id, offset)
            }
        }
        // A different folder gets a new scroll view, so that its items start at the top.
        .id(card.url)
        .coordinateSpace(.named(Self.listSpace))
        .frame(height: card.contentHeight, alignment: .top)
        .showsSelection(of: model, in: card)
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
        // A different folder gets a new scroll view, so that its items start at the top.
        .id(card.url)
        .coordinateSpace(.named(Self.listSpace))
        .frame(height: card.contentHeight, alignment: .top)
        .showsSelection(of: model, in: card)
    }

    private func iconCell(_ entry: FileEntry) -> some View {
        let isSelected = isSelected(entry)
        return VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                .resizable()
                .frame(width: CardLayout.iconSize, height: CardLayout.iconSize)
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? Color.primary.opacity(0.1) : .clear)
                )
            if isRenaming(entry) {
                RenameField(model: model)
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            } else {
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
        }
        .padding(.top, 4)
        .frame(width: CardLayout.iconCellWidth(width: card.width), height: CardLayout.iconCellHeight, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { model.select(entry.url, in: card.id) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { open(entry) })
        .onDrag { NSItemProvider(object: entry.url as NSURL) }
    }

    /// The double-click, as in Finder. With the Command key, a folder opens in a child card.
    private func open(_ entry: FileEntry) {
        model.open(entry.url, in: card.id, inChildCard: NSEvent.modifierFlags.contains(.command))
    }

    private func isSelected(_ entry: FileEntry) -> Bool {
        model.selection == ItemRef(cardID: card.id, url: entry.url)
    }

    private func isRenaming(_ entry: FileEntry) -> Bool {
        model.renaming == ItemRef(cardID: card.id, url: entry.url)
    }

    private func row(_ entry: FileEntry, index: Int) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
                if isRenaming(entry) {
                    RenameField(model: model)
                } else {
                    Text(entry.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
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
        .background(rowBackground(isHighlighted: isSelected(entry), index: index))
        .contentShape(Rectangle())
        .onTapGesture { model.select(entry.url, in: card.id) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { open(entry) })
        .onDrag { NSItemProvider(object: entry.url as NSURL) }
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

private extension View {
    /// Scrolls the item area of the card when the selected item is not fully in view,
    /// for example after an arrow key. The model makes the decision (`scrollEdge`).
    func showsSelection(of model: CanvasModel, in card: FolderCard) -> some View {
        ScrollViewReader { proxy in
            onChange(of: model.selection) { _, selection in
                guard let selection, selection.cardID == card.id else { return }
                switch model.scrollEdge(for: selection) {
                case .top: proxy.scrollTo(selection.url, anchor: .top)
                case .bottom: proxy.scrollTo(selection.url, anchor: .bottom)
                case nil: break
                }
            }
        }
    }
}

/// The name field of the item that the user renames. Return keeps the new name and Escape cancels.
private struct RenameField: View {
    @Bindable var model: CanvasModel
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Name", text: $model.renameDraft)
            .textFieldStyle(.plain)
            .padding(.horizontal, 3)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.accentColor, lineWidth: 1.5))
            .focused($isFocused)
            .onSubmit { model.commitRename() }
            .onExitCommand { model.cancelRename() }
            // The field cannot get the focus in the same update that adds it to the window.
            .onAppear { DispatchQueue.main.async { isFocused = true } }
            .onChange(of: isFocused) { _, focused in
                if focused {
                    selectNameWithoutExtension()
                } else {
                    model.commitRename()
                }
            }
    }

    /// As in Finder, the rename starts with the name selected, but not the extension.
    private func selectNameWithoutExtension() {
        let name = model.renameDraft as NSString
        let length = (name.deletingPathExtension as NSString).length
        DispatchQueue.main.async {
            // The field editor is the first responder while a text field has the focus.
            guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
            editor.setSelectedRange(NSRange(location: 0, length: length))
        }
    }
}

/// Lets a card receive dragged files, from a different card or from Finder.
private struct CardDropDelegate: DropDelegate {
    let cardID: FolderCard.ID
    let model: CanvasModel
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    /// Sets the cursor badge: a copy shows a plus sign.
    func dropUpdated(info: DropInfo) -> DropProposal? {
        switch model.dropKind(for: Self.draggedURLs, on: cardID, optionKey: Self.isOptionKeyDown) {
        case .move: DropProposal(operation: .move)
        case .copy: DropProposal(operation: .copy)
        case nil: DropProposal(operation: .forbidden)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        return model.drop(Self.draggedURLs, on: cardID, optionKey: Self.isOptionKeyDown)
    }

    /// The files of the drag in progress. The drag pasteboard gives them immediately.
    private static var draggedURLs: [URL] {
        let objects = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        return objects as? [URL] ?? []
    }

    private static var isOptionKeyDown: Bool {
        NSEvent.modifierFlags.contains(.option)
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
