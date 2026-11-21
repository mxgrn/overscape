import Foundation
import Observation

struct FileEntry: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let modified: Date?

    var id: URL { url }
}

/// How a card shows its items, like the view modes in Finder.
enum CardViewMode: String, Codable {
    case list
    case icons
}

struct FolderCard: Identifiable {
    var id = UUID()
    let url: URL
    var position: CGPoint
    var entries: [FileEntry]
    /// The card that this card was opened from. Nil for a dropped folder.
    var parentID: UUID? = nil
    /// How far the file list is scrolled (0 or negative), in canvas points.
    var scrollOffset: CGFloat = 0
    var viewMode: CardViewMode = .list
    var width: CGFloat = CardLayout.defaultWidth
    /// Nil means that the height comes from the content. When the user resizes the card
    /// vertically, the card gets a fixed height.
    var fixedHeight: CGFloat? = nil

    func itemCenterY(index: Int) -> CGFloat {
        CardLayout.itemCenterY(
            index: index, mode: viewMode, iconColumns: iconColumns,
            contentHeight: contentHeight, scrollOffset: scrollOffset
        )
    }

    var title: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
    var iconColumns: Int { CardLayout.iconColumns(width: width) }
    var height: CGFloat { fixedHeight ?? CardLayout.height(entryCount: entries.count, mode: viewMode, width: width) }
    /// The height of the item area (the list or the icon grid).
    var contentHeight: CGFloat { height - CardLayout.contentTop(mode: viewMode) }
    var frame: CGRect { CGRect(origin: position, size: CGSize(width: width, height: height)) }
}

/// The edges of a card that a resize moves. A corner is two edges.
struct CardEdges: OptionSet, Hashable {
    let rawValue: Int

    static let left = CardEdges(rawValue: 1 << 0)
    static let top = CardEdges(rawValue: 1 << 1)
    static let right = CardEdges(rawValue: 1 << 2)
    static let bottom = CardEdges(rawValue: 1 << 3)
}

/// Card sizes in canvas points. The card view and the model both use them.
enum CardLayout {
    static let defaultWidth: CGFloat = 490
    static let minWidth: CGFloat = 320
    static let headerHeight: CGFloat = 32
    static let columnHeaderHeight: CGFloat = 24
    static let dividerHeight: CGFloat = 1
    static let rowHeight: CGFloat = 27
    /// The maximum height of the item area when the height comes from the content.
    static let maxListHeight: CGFloat = 640
    /// The minimum card height: the header, the column headers and one row.
    static var minHeight: CGFloat { listTop + rowHeight }
    /// Horizontal space between a card and the cards opened from it.
    static let childSpacing: CGFloat = 60
    /// Vertical space between cards opened from the same card.
    static let siblingSpacing: CGFloat = 20
    /// The thickness of the area along an edge that resizes the card.
    static let resizeEdgeThickness: CGFloat = 8
    /// The size of the area at a corner that resizes the card.
    static let resizeCornerSize: CGFloat = 16

    /// Icon mode: the size of one icon, as in Finder.
    static let iconSize: CGFloat = 64
    /// Icon mode: the minimum width of one cell. The card width sets the number of columns.
    static let iconMinCellWidth: CGFloat = 110
    static let gridPadding: CGFloat = 10
    /// Icon mode: the height of one cell (icon, space and a name of two lines).
    static let iconCellHeight: CGFloat = 108

    static func iconColumns(width: CGFloat) -> Int {
        max(1, Int((width - 2 * gridPadding) / iconMinCellWidth))
    }

    static func iconCellWidth(width: CGFloat) -> CGFloat {
        (width - 2 * gridPadding) / CGFloat(iconColumns(width: width))
    }

    static var listTop: CGFloat { headerHeight + dividerHeight + columnHeaderHeight + dividerHeight }

    /// The top of the item area. Icon mode has no column headers.
    static func contentTop(mode: CardViewMode) -> CGFloat {
        switch mode {
        case .list: listTop
        case .icons: headerHeight + dividerHeight
        }
    }

    static func listHeight(entryCount: Int) -> CGFloat {
        min(CGFloat(max(entryCount, 1)) * rowHeight, maxListHeight)
    }

    static func iconRowCount(entryCount: Int, columns: Int) -> Int {
        (max(entryCount, 1) + columns - 1) / columns
    }

    static func gridHeight(entryCount: Int, width: CGFloat) -> CGFloat {
        let rows = iconRowCount(entryCount: entryCount, columns: iconColumns(width: width))
        return min(CGFloat(rows) * iconCellHeight + 2 * gridPadding, maxListHeight)
    }

    /// The height of the item area when the height comes from the content.
    /// The item area scrolls when the items need more space.
    static func contentHeight(entryCount: Int, mode: CardViewMode, width: CGFloat) -> CGFloat {
        switch mode {
        case .list: listHeight(entryCount: entryCount)
        case .icons: gridHeight(entryCount: entryCount, width: width)
        }
    }

    /// The card height when the height comes from the content.
    static func height(entryCount: Int, mode: CardViewMode = .list, width: CGFloat = defaultWidth) -> CGFloat {
        contentTop(mode: mode) + contentHeight(entryCount: entryCount, mode: mode, width: width)
    }

    /// The vertical center of an item (a row or an icon cell), from the top of the card.
    /// When the item is scrolled out of view, the value stops at the top or bottom edge of the item area.
    static func itemCenterY(
        index: Int, mode: CardViewMode, iconColumns: Int, contentHeight: CGFloat, scrollOffset: CGFloat
    ) -> CGFloat {
        let top = contentTop(mode: mode)
        let center: CGFloat
        switch mode {
        case .list:
            center = (CGFloat(index) + 0.5) * rowHeight
        case .icons:
            center = gridPadding + (CGFloat(index / iconColumns) + 0.5) * iconCellHeight
        }
        let y = top + scrollOffset + center
        return min(max(y, top), top + contentHeight)
    }
}

struct Connection: Identifiable {
    let id: FolderCard.ID // The child card.
    let start: CGPoint
    let end: CGPoint
}

enum FolderLoader {
    /// Lists the visible items of a folder, newest first.
    static func entries(in folder: URL) -> [FileEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .localizedNameKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory ?? false
            return FileEntry(
                url: url,
                name: values?.localizedName ?? url.lastPathComponent,
                isDirectory: isDirectory,
                size: isDirectory ? nil : values?.fileSize.map(Int64.init),
                modified: values?.contentModificationDate
            )
        }
        .sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}

/// The saved state of the canvas: the open cards and the viewport.
struct CanvasSnapshot: Codable, Equatable {
    struct Card: Codable, Equatable {
        let id: UUID
        let path: String
        let x: CGFloat
        let y: CGFloat
        let parentID: UUID?
        /// Nil in files from versions without view modes. Nil means list mode.
        var viewMode: CardViewMode? = nil
        /// Nil in files from versions without resize. Nil means the default width.
        var width: CGFloat? = nil
        /// Nil means that the height comes from the content.
        var height: CGFloat? = nil
    }

    var cards: [Card]
    var zoom: CGFloat
    var panX: CGFloat
    var panY: CGFloat
}

/// Reads and writes the canvas snapshot as a JSON file.
enum SnapshotStore {
    static var defaultURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Overscape", isDirectory: true)
            .appendingPathComponent("canvas.json")
    }

    static func save(_ snapshot: CanvasSnapshot, to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }

    /// Returns nil when there is no file or the file is not valid.
    static func load(from url: URL = defaultURL) -> CanvasSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CanvasSnapshot.self, from: data)
    }
}

@MainActor
@Observable
final class CanvasModel {
    var cards: [FolderCard] = []
    /// The card under the cursor. Keyboard commands for a card go to this card.
    private(set) var hoveredCardID: FolderCard.ID?

    /// Viewport: a canvas point `p` shows at `p * zoom + pan` in the view.
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
    /// True when the current two-finger scroll pans the canvas.
    private(set) var isScrollPanning = false

    static let zoomRange: ClosedRange<CGFloat> = 0.25...3

    var snapshot: CanvasSnapshot {
        CanvasSnapshot(
            cards: cards.map {
                .init(
                    id: $0.id, path: $0.url.path, x: $0.position.x, y: $0.position.y, parentID: $0.parentID,
                    viewMode: $0.viewMode, width: $0.width, height: $0.fixedHeight
                )
            },
            zoom: zoom,
            panX: pan.width,
            panY: pan.height
        )
    }

    /// Replaces the canvas with the saved state. The file lists are read again from disk.
    /// A card whose folder does not exist is not restored. The cards opened from it are also not restored.
    func restore(_ snapshot: CanvasSnapshot) {
        let saved = Dictionary(snapshot.cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var kept: [UUID: Bool] = [:]
        func isKept(_ card: CanvasSnapshot.Card) -> Bool {
            if let known = kept[card.id] { return known }
            kept[card.id] = false // Stops a loop in a damaged file.
            var result = FolderLoader.isDirectory(URL(fileURLWithPath: card.path))
            if result, let parentID = card.parentID {
                result = saved[parentID].map(isKept) ?? false
            }
            kept[card.id] = result
            return result
        }

        cards = snapshot.cards.filter(isKept).map { card in
            let url = URL(fileURLWithPath: card.path)
            return FolderCard(
                id: card.id,
                url: url,
                position: CGPoint(x: card.x, y: card.y),
                entries: FolderLoader.entries(in: url),
                parentID: card.parentID,
                viewMode: card.viewMode ?? .list,
                width: max(card.width ?? CardLayout.defaultWidth, CardLayout.minWidth),
                fixedHeight: card.height.map { max($0, CardLayout.minHeight) }
            )
        }
        zoom = min(max(snapshot.zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        pan = CGSize(width: snapshot.panX, height: snapshot.panY)
    }

    /// Changes the zoom by `factor` and keeps the canvas point under `anchor` (view coordinates) in place.
    func zoom(by factor: CGFloat, around anchor: CGPoint) {
        let newZoom = min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let ratio = newZoom / zoom
        pan = CGSize(
            width: anchor.x - (anchor.x - pan.width) * ratio,
            height: anchor.y - (anchor.y - pan.height) * ratio
        )
        zoom = newZoom
    }

    func pan(by delta: CGSize) {
        pan.width += delta.width
        pan.height += delta.height
    }

    /// Starts a two-finger scroll at `point` (view coordinates). `point` is nil when the scroll
    /// starts outside the canvas. The scroll pans the canvas only when it starts on empty canvas.
    func beginScroll(at point: CGPoint?) {
        guard let point else {
            isScrollPanning = false
            return
        }
        let canvasPoint = canvasPoint(fromView: point)
        isScrollPanning = !cards.contains { $0.frame.contains(canvasPoint) }
    }

    /// Pans the canvas during a two-finger scroll that started on empty canvas, also when a card
    /// is under the cursor now. Returns false when the scroll does not pan. The event then continues.
    @discardableResult
    func scroll(by delta: CGSize) -> Bool {
        guard isScrollPanning else { return false }
        pan(by: delta)
        return true
    }

    func canvasPoint(fromView point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - pan.width) / zoom, y: (point.y - pan.height) / zoom)
    }

    /// Adds a card for each dropped folder. Returns false when nothing was a folder.
    @discardableResult
    func addFolders(_ urls: [URL], at location: CGPoint) -> Bool {
        let folders = urls.filter(FolderLoader.isDirectory)
        for (index, folder) in folders.enumerated() {
            let offset = CGFloat(index) * 30
            cards.append(FolderCard(
                url: folder,
                position: CGPoint(x: location.x + offset, y: location.y + offset),
                entries: FolderLoader.entries(in: folder)
            ))
        }
        return !folders.isEmpty
    }

    func move(_ id: FolderCard.ID, to position: CGPoint) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].position = position
    }

    /// Changes the card frame while the user drags the `edges` of the card by `translation` (canvas points).
    /// `start` is the card frame at the start of the drag. The opposite edges stay in place.
    /// The card does not become smaller than the minimum size.
    /// When the top or the bottom edge moves, the card gets a fixed height.
    func resize(_ id: FolderCard.ID, edges: CardEdges, from start: CGRect, by translation: CGSize) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        var frame = start
        if edges.contains(.left) {
            frame.origin.x = min(start.minX + translation.width, start.maxX - CardLayout.minWidth)
            frame.size.width = start.maxX - frame.minX
        }
        if edges.contains(.right) {
            frame.size.width = max(start.width + translation.width, CardLayout.minWidth)
        }
        if edges.contains(.top) {
            frame.origin.y = min(start.minY + translation.height, start.maxY - CardLayout.minHeight)
            frame.size.height = start.maxY - frame.minY
        }
        if edges.contains(.bottom) {
            frame.size.height = max(start.height + translation.height, CardLayout.minHeight)
        }
        cards[index].position = frame.origin
        cards[index].width = frame.width
        if !edges.isDisjoint(with: [.top, .bottom]) {
            cards[index].fixedHeight = frame.height
        }
    }

    /// Moves the card to the end of the list, so that it draws on top.
    func bringToFront(_ id: FolderCard.ID) {
        guard let index = cards.firstIndex(where: { $0.id == id }), index != cards.count - 1 else { return }
        cards.append(cards.remove(at: index))
    }

    /// Opens a card for `folder` (a subfolder in the parent card) to the right of the parent.
    /// A parent can have many child cards. They stay in the same vertical order as their rows
    /// in the parent, so the connector lines do not cross. When there is no space for the new
    /// card, the sibling cards below it move down.
    func openChild(of parentID: FolderCard.ID, folder: URL) {
        guard let parent = cards.first(where: { $0.id == parentID }),
              let rowIndex = parent.entries.firstIndex(where: { $0.url == folder })
        else { return }

        if let existing = cards.first(where: { $0.parentID == parentID && $0.url == folder }) {
            bringToFront(existing.id)
            return
        }

        let entries = FolderLoader.entries(in: folder)
        let height = CardLayout.height(entryCount: entries.count)
        let spacing = CardLayout.siblingSpacing

        // The open siblings, in the order of their rows in the parent.
        let siblings = cards
            .filter { $0.parentID == parentID }
            .compactMap { card in parent.entries.firstIndex { $0.url == card.url }.map { (index: $0, card: card) } }
            .sorted { $0.index < $1.index }
        let above = siblings.last { $0.index < rowIndex }?.card
        let below = siblings.filter { $0.index > rowIndex }.map(\.card)

        // Start level with the clicked row, then stay between the sibling above and the sibling below.
        let rowY = parent.itemCenterY(index: rowIndex)
        var y = parent.position.y + rowY - CardLayout.headerHeight / 2
        if let first = below.first {
            y = min(y, first.position.y - height - spacing)
        }
        if let above {
            y = max(y, above.position.y + above.height + spacing)
        }

        // Move the siblings below down where they would overlap.
        var bottom = y + height
        for sibling in below {
            let top = max(sibling.position.y, bottom + spacing)
            if top != sibling.position.y {
                move(sibling.id, to: CGPoint(x: sibling.position.x, y: top))
            }
            bottom = top + sibling.height
        }

        cards.append(FolderCard(
            url: folder,
            position: CGPoint(x: parent.position.x + parent.width + CardLayout.childSpacing, y: y),
            entries: entries,
            parentID: parentID
        ))
    }

    func setScrollOffset(_ id: FolderCard.ID, _ offset: CGFloat) {
        guard let index = cards.firstIndex(where: { $0.id == id }), cards[index].scrollOffset != offset else { return }
        cards[index].scrollOffset = offset
    }

    func setHovered(_ id: FolderCard.ID, _ isHovered: Bool) {
        if isHovered {
            hoveredCardID = id
        } else if hoveredCardID == id {
            hoveredCardID = nil
        }
    }

    /// Sets the view mode of the card under the cursor. Returns false when there is no card under the cursor.
    @discardableResult
    func setViewModeOfHoveredCard(_ mode: CardViewMode) -> Bool {
        guard let index = cards.firstIndex(where: { $0.id == hoveredCardID }) else { return false }
        if cards[index].viewMode != mode {
            cards[index].viewMode = mode
            cards[index].scrollOffset = 0 // The new item area starts at the top.
        }
        return true
    }

    /// Lines from a row in a parent card to the header of the child card, in canvas points.
    var connections: [Connection] {
        cards.compactMap { child in
            guard let parent = cards.first(where: { $0.id == child.parentID }),
                  let rowIndex = parent.entries.firstIndex(where: { $0.url == child.url })
            else { return nil }
            let rowY = parent.itemCenterY(index: rowIndex)
            return Connection(
                id: child.id,
                start: CGPoint(x: parent.position.x + parent.width, y: parent.position.y + rowY),
                end: CGPoint(x: child.position.x, y: child.position.y + CardLayout.headerHeight / 2)
            )
        }
    }

    /// Closes the card and all cards that were opened from it.
    func close(_ id: FolderCard.ID) {
        var closing: Set<FolderCard.ID> = [id]
        var found = true
        while found {
            found = false
            for card in cards where !closing.contains(card.id) {
                if let parentID = card.parentID, closing.contains(parentID) {
                    closing.insert(card.id)
                    found = true
                }
            }
        }
        cards.removeAll { closing.contains($0.id) }
        if let hoveredCardID, closing.contains(hoveredCardID) {
            self.hoveredCardID = nil
        }
    }
}
