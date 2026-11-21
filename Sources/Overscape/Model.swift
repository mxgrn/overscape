import AppKit
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
    /// The folder of the card. It changes when the folder gets a new name.
    var url: URL
    var position: CGPoint
    var entries: [FileEntry]
    /// The card that this card was opened from. Nil for a dropped folder.
    /// The connector line shows only while the folder of this card is an item in that card.
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
        let range = itemRange(index: index, mode: mode, iconColumns: iconColumns)
        let y = top + scrollOffset + (range.lowerBound + range.upperBound) / 2
        return min(max(y, top), top + contentHeight)
    }

    /// The top and the bottom of an item (a row or an icon cell), from the top of the items.
    static func itemRange(index: Int, mode: CardViewMode, iconColumns: Int) -> ClosedRange<CGFloat> {
        switch mode {
        case .list:
            let top = CGFloat(index) * rowHeight
            return top...(top + rowHeight)
        case .icons:
            let top = gridPadding + CGFloat(index / iconColumns) * iconCellHeight
            return top...(top + iconCellHeight)
        }
    }

    /// The edge of the item area that an item must go to, so that the item is fully in view.
    /// Nil when the item is fully in view. A difference of less than 1 point is ignored,
    /// because the scroll offset is not always a full number when the canvas has a zoom.
    static func scrollEdge(
        index: Int, mode: CardViewMode, iconColumns: Int, contentHeight: CGFloat, scrollOffset: CGFloat
    ) -> ScrollEdge? {
        let range = itemRange(index: index, mode: mode, iconColumns: iconColumns)
        if range.lowerBound + scrollOffset < -1 { return .top }
        if range.upperBound + scrollOffset > contentHeight + 1 { return .bottom }
        return nil
    }
}

/// An edge of the item area of a card.
enum ScrollEdge {
    case top
    case bottom
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
        // A URL keeps the values that it read before. Remove them, so that the answer comes from disk.
        var url = url
        url.removeAllCachedResourceValues()
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    /// A package (an app, for example) is a folder that Finder shows as one file.
    static func isPackage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
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

/// An item (a file or a folder) in a card.
struct ItemRef: Hashable {
    let cardID: FolderCard.ID
    let url: URL
}

/// How items go into a folder.
enum TransferKind {
    case move
    case copy
}

/// The direction of an arrow key.
enum ArrowDirection {
    case up
    case down
    case left
    case right
}

/// A keyboard command for the canvas.
enum CanvasCommand: Equatable {
    case viewMode(CardViewMode)
    case moveSelection(ArrowDirection)
    case openSelection
    case quickLook
    case showParentFolder
    case closeCard
    case rename
    case newFolder
    case moveToTrash
    case copy
    case paste
    case pasteAndMove
    case undo
}

/// A file operation that `undo` can reverse.
enum UndoStep {
    case rename(from: URL, to: URL)
    case move([(from: URL, to: URL)])
    case copy([URL])
    case newFolder(URL)
    case trash(original: URL, trashed: URL)
}

@MainActor
@Observable
final class CanvasModel {
    var cards: [FolderCard] = []
    /// The card under the cursor. Keyboard commands for a card go to this card.
    private(set) var hoveredCardID: FolderCard.ID?

    /// The selected item. The canvas has not more than one selected item.
    private(set) var selection: ItemRef? {
        // While Quick Look is open, it shows the selected item. Without a selected item, it closes.
        didSet { if quickLookURL != nil { quickLookURL = selection?.url } }
    }
    /// The item that Quick Look shows. Nil while Quick Look is closed.
    /// The view sets nil when the user closes the Quick Look panel.
    var quickLookURL: URL?
    /// The item that the user renames at this time.
    private(set) var renaming: ItemRef?
    /// The text in the name field during a rename.
    var renameDraft = ""
    /// The message of the last file operation that failed. The view shows it in an alert.
    var errorMessage: String?
    /// Copy and paste use this pasteboard. Tests set a different pasteboard.
    @ObservationIgnored var pasteboard: NSPasteboard = .general
    /// Moves an item to the Trash. Tests set a different function to keep the Trash clean.
    @ObservationIgnored var trash: (URL) throws -> URL? = FileOperations.trash
    /// Opens a file in its default app. Returns false when the file did not open.
    /// Tests set a different function, so that no app starts.
    @ObservationIgnored var openFile: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    @ObservationIgnored private var undoSteps: [UndoStep] = []

    /// Viewport: a canvas point `p` shows at `p * zoom + pan` in the view.
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
    /// The size of the canvas view. The view sets it. The model needs it to find the center of the visible canvas.
    @ObservationIgnored var viewSize: CGSize = .zero
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
    /// starts outside the canvas. The scroll pans the canvas when it starts on empty canvas.
    /// With the Control key, it also pans when it starts on a card.
    func beginScroll(at point: CGPoint?, withControl: Bool = false) {
        guard let point else {
            isScrollPanning = false
            return
        }
        let canvasPoint = canvasPoint(fromView: point)
        isScrollPanning = withControl || !cards.contains { $0.frame.contains(canvasPoint) }
    }

    /// Pans the canvas during a two-finger scroll that pans from its start (see `beginScroll`), also
    /// when a card is under the cursor now. Returns false when the scroll does not pan. The event then continues.
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

    /// Adds a card for the folder at the center of the visible canvas.
    /// If a card is already at that position, the new card goes down and to the right, so that both show.
    /// Returns false when `url` is not a folder.
    @discardableResult
    func addFolderAtCenter(_ url: URL) -> Bool {
        guard FolderLoader.isDirectory(url) else { return false }
        var card = FolderCard(url: url, position: .zero, entries: FolderLoader.entries(in: url))
        let center = canvasPoint(fromView: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2))
        card.position = CGPoint(x: center.x - card.width / 2, y: center.y - card.height / 2)
        while cards.contains(where: { $0.position == card.position }) {
            card.position.x += 30
            card.position.y += 30
        }
        cards.append(card)
        return true
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

    /// Does the double-click on an item in a card. As in Finder, a file opens in its default app
    /// and a folder shows in the same card. A package (an app, for example) opens as a file.
    /// With `inChildCard` (the Command key), a folder opens in a child card and a file does nothing.
    func open(_ url: URL, in cardID: FolderCard.ID, inChildCard: Bool = false) {
        guard let entry = cards.first(where: { $0.id == cardID })?.entries.first(where: { $0.url == url })
        else { return }
        if inChildCard {
            if entry.isDirectory { openChild(of: cardID, folder: url) }
        } else if entry.isDirectory, !FolderLoader.isPackage(url) {
            show(url, in: cardID)
        } else if !openFile(url) {
            errorMessage = "The file “\(entry.name)” did not open."
        }
    }

    /// Shows the parent folder in the card under the cursor and selects the folder that the card
    /// showed before, as Command-Up does in Finder.
    /// Returns false when there is no card under the cursor or the card shows the top folder of the disk.
    @discardableResult
    func showParentFolderInHoveredCard() -> Bool {
        guard let card = cards.first(where: { $0.id == hoveredCardID }), card.url.path != "/" else { return false }
        show(card.url.deletingLastPathComponent(), in: card.id)
        select(itemNamed: card.url.lastPathComponent, in: card.id)
        return true
    }

    /// Makes the card show a different folder. The card keeps its position and its size:
    /// it gets its height at this time as a fixed height, also when the new folder has more or fewer items.
    /// The card that it was opened from and the cards that were opened from it stay open and stay related.
    /// Their connector lines show again when the folders agree with the rows again (`connections`).
    private func show(_ folder: URL, in cardID: FolderCard.ID) {
        commitRename()
        guard FolderLoader.isDirectory(folder),
              let index = cards.firstIndex(where: { $0.id == cardID })
        else { return }
        cards[index].fixedHeight = cards[index].height
        cards[index].url = folder
        cards[index].entries = FolderLoader.entries(in: folder)
        cards[index].scrollOffset = 0 // The new item area starts at the top.
        if selection?.cardID == cardID { selection = nil }
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
    /// A child card has no line while its folder is not an item in the parent card. This occurs
    /// when one of the two cards shows a different folder after a double-click or Command-Up.
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

    /// Closes the card. A card that was opened from it also closes if a line connects the two cards
    /// at this time (`connections`). The same rule applies to the cards opened from each closed card.
    /// A card without a line stays open and becomes an independent card.
    func close(_ id: FolderCard.ID) {
        let linked = Set(connections.map(\.id))
        var closing: Set<FolderCard.ID> = [id]
        var found = true
        while found {
            found = false
            for card in cards where linked.contains(card.id) && !closing.contains(card.id) {
                if let parentID = card.parentID, closing.contains(parentID) {
                    closing.insert(card.id)
                    found = true
                }
            }
        }
        cards.removeAll { closing.contains($0.id) }
        for index in cards.indices {
            if let parentID = cards[index].parentID, closing.contains(parentID) {
                cards[index].parentID = nil
            }
        }
        if let hoveredCardID, closing.contains(hoveredCardID) {
            self.hoveredCardID = nil
        }
        if let selection, closing.contains(selection.cardID) {
            self.selection = nil
        }
        if let renaming, closing.contains(renaming.cardID) {
            self.renaming = nil
        }
    }

    /// Closes the card under the cursor, as `close` does.
    /// Returns false when there is no card under the cursor.
    @discardableResult
    func closeHoveredCard() -> Bool {
        guard let hoveredCardID else { return false }
        close(hoveredCardID)
        return true
    }

    // MARK: - Selection

    /// Selects an item. A rename of a different item ends and keeps the new name.
    /// An item that the card does not show is ignored.
    func select(_ url: URL, in cardID: FolderCard.ID) {
        let item = ItemRef(cardID: cardID, url: url)
        if renaming != item { commitRename() }
        guard isShown(item) else { return }
        selection = item
    }

    /// Removes the selection. A rename ends and keeps the new name.
    func clearSelection() {
        commitRename()
        selection = nil
    }

    /// Moves the selection in the card under the cursor to the adjacent item, as the arrow keys do in Finder.
    /// If the card has no selected item, Down and Right select the first item and Up and Left select the last item.
    /// In list mode, Left and Right do nothing. In icon mode, Left and Right continue on the adjacent line.
    /// While Quick Look is open, the selection moves in the card that has the selected item.
    /// Returns false when there is no card under the cursor.
    @discardableResult
    func moveSelectionInHoveredCard(_ direction: ArrowDirection) -> Bool {
        // While Quick Look is open, the cursor can be on the Quick Look panel and not on a card.
        // The keys then go to the card that has the selected item.
        let cardID = quickLookURL != nil ? selection?.cardID : hoveredCardID
        guard let card = cards.first(where: { $0.id == cardID }) else { return false }
        let isForward = direction == .down || direction == .right
        let isHorizontal = direction == .left || direction == .right
        if card.viewMode == .list, isHorizontal { return true }
        guard let last = card.entries.indices.last else { return true }

        var index = isForward ? 0 : last
        if let selection, selection.cardID == card.id,
           let current = card.entries.firstIndex(where: { $0.url == selection.url }) {
            let columns = card.viewMode == .icons ? card.iconColumns : 1
            let target = current + (isForward ? 1 : -1) * (isHorizontal ? 1 : columns)
            if card.entries.indices.contains(target) {
                index = target
            } else if direction == .down, current / columns < last / columns {
                // The last line of icons is shorter than the line above it.
                index = last
            } else {
                index = current
            }
        }
        select(card.entries[index].url, in: card.id)
        return true
    }

    /// Opens the selected item as a double-click does: a file opens in its default app and a folder
    /// shows in the same card. Returns false when no item is selected.
    @discardableResult
    func openSelection() -> Bool {
        guard let selection, isShown(selection) else { return false }
        open(selection.url, in: selection.cardID)
        return true
    }

    /// Opens Quick Look for the selected item, as the Space key does in Finder.
    /// If Quick Look is open, it closes. Returns false when Quick Look is closed and no item is selected.
    @discardableResult
    func toggleQuickLook() -> Bool {
        if quickLookURL != nil {
            quickLookURL = nil
            return true
        }
        guard let selection, isShown(selection) else { return false }
        quickLookURL = selection.url
        return true
    }

    /// The edge of the item area that the item must scroll to, so that the item is fully in view.
    /// Nil when the item is fully in view or the card does not show it. The card view uses this
    /// to show the selected item. The model makes the decision, because `scrollTo` without an anchor
    /// also moves an item that is in view when the card is not fully in the window.
    func scrollEdge(for item: ItemRef) -> ScrollEdge? {
        guard let card = cards.first(where: { $0.id == item.cardID }),
              let index = card.entries.firstIndex(where: { $0.url == item.url })
        else { return nil }
        return CardLayout.scrollEdge(
            index: index, mode: card.viewMode, iconColumns: card.iconColumns,
            contentHeight: card.contentHeight, scrollOffset: card.scrollOffset
        )
    }

    private func isShown(_ item: ItemRef) -> Bool {
        cards.first { $0.id == item.cardID }?.entries.contains { $0.url == item.url } ?? false
    }

    private func select(itemNamed name: String, in cardID: FolderCard.ID) {
        let entry = cards.first { $0.id == cardID }?.entries.first { $0.url.lastPathComponent == name }
        selection = entry.map { ItemRef(cardID: cardID, url: $0.url) }
    }

    // MARK: - File operations

    /// Does the keyboard command. Returns false when the command had no effect.
    @discardableResult
    func perform(_ command: CanvasCommand) -> Bool {
        switch command {
        case .viewMode(let mode): setViewModeOfHoveredCard(mode)
        case .moveSelection(let direction): moveSelectionInHoveredCard(direction)
        case .openSelection: openSelection()
        case .quickLook: toggleQuickLook()
        case .showParentFolder: showParentFolderInHoveredCard()
        case .closeCard: closeHoveredCard()
        case .rename: beginRename()
        case .newFolder: newFolder()
        case .moveToTrash: trashSelection()
        case .copy: copySelection()
        case .paste: paste()
        case .pasteAndMove: paste(move: true)
        case .undo: undo()
        }
    }

    /// Reads the file lists of all cards from disk again. A card whose folder does not exist closes.
    /// The cards opened from a closed card also close if their folders do not exist.
    func reload() {
        for index in cards.indices {
            let entries = FolderLoader.entries(in: cards[index].url)
            if entries != cards[index].entries { cards[index].entries = entries }
        }
        let stale = cards.filter { !FolderLoader.isDirectory($0.url) }
        for card in stale { close(card.id) }
        if let selection, !isShown(selection) { self.selection = nil }
        if let renaming, !isShown(renaming) { self.renaming = nil }
    }

    /// Does a file operation. When it fails, the view gets the error message and the result is false.
    @discardableResult
    private func attempt(_ operation: () throws -> Void) -> Bool {
        do {
            try operation()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Starts the rename of the selected item. Returns false when no item is selected.
    @discardableResult
    func beginRename() -> Bool {
        guard let selection, isShown(selection) else { return false }
        renaming = selection
        renameDraft = selection.url.lastPathComponent
        return true
    }

    /// Ends the rename and does not change the name.
    func cancelRename() {
        renaming = nil
    }

    /// Ends the rename and gives the item the name from the name field.
    func commitRename() {
        guard let item = renaming else { return }
        renaming = nil
        rename(item, to: renameDraft)
    }

    /// Changes the name of an item on disk. A name with only spaces is ignored.
    /// The open cards for a renamed folder, and for the folders in it, stay open.
    func rename(_ item: ItemRef, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != item.url.lastPathComponent else { return }
        guard !name.hasPrefix("."), !name.contains("/") else {
            errorMessage = "The name “\(name)” is not permitted. A name cannot start with a dot or contain a slash."
            return
        }
        let target = item.url.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: item.url, to: target)
        } catch CocoaError.fileWriteFileExists {
            errorMessage = "The name “\(name)” is already taken. Use a different name."
            return
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        undoSteps.append(.rename(from: item.url, to: target))
        moveCards(from: item.url, to: target)
        reload()
        select(itemNamed: name, in: item.cardID)
    }

    /// Gives the cards for a renamed folder, and for the folders in it, their new URLs.
    private func moveCards(from old: URL, to new: URL) {
        for index in cards.indices {
            let path = cards[index].url.path
            if path == old.path || path.hasPrefix(old.path + "/") {
                cards[index].url = URL(fileURLWithPath: new.path + path.dropFirst(old.path.count))
            }
        }
    }

    /// Makes a new folder in the folder of the card under the cursor, as in Finder.
    /// The new folder becomes the selected item and its rename starts.
    /// Returns false when there is no card under the cursor.
    @discardableResult
    func newFolder() -> Bool {
        guard let cardID = hoveredCardID else { return false }
        // A rename can change the URL of the card. Thus get the URL after the rename ends.
        commitRename()
        guard let folder = cards.first(where: { $0.id == cardID })?.url else { return false }
        var created: URL?
        guard attempt({ created = try FileOperations.newFolder(in: folder) }), let created else { return true }
        undoSteps.append(.newFolder(created))
        reload()
        select(itemNamed: created.lastPathComponent, in: cardID)
        beginRename()
        return true
    }

    /// Moves the selected item to the Trash. Returns false when no item is selected.
    @discardableResult
    func trashSelection() -> Bool {
        guard let item = selection else { return false }
        var trashed: URL?
        if attempt({ trashed = try trash(item.url) }), let trashed {
            undoSteps.append(.trash(original: item.url, trashed: trashed))
        }
        reload()
        return true
    }

    /// Puts the selected item on the pasteboard. Returns false when no item is selected.
    @discardableResult
    func copySelection() -> Bool {
        guard let item = selection else { return false }
        pasteboard.clearContents()
        pasteboard.writeObjects([item.url as NSURL])
        return true
    }

    /// Copies (or moves) the files on the pasteboard into the folder of the card under the cursor.
    /// Returns false when no item went into the folder.
    @discardableResult
    func paste(move: Bool = false) -> Bool {
        guard let cardID = hoveredCardID else { return false }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        return transfer(urls as? [URL] ?? [], to: cardID, kind: move ? .move : .copy)
    }

    /// The Finder rule for a drop on a card: a move on the same volume and a copy between different volumes.
    /// With the Option key, a drop always makes a copy. Nil means that the card cannot get the items.
    func dropKind(for urls: [URL], on cardID: FolderCard.ID, optionKey: Bool) -> TransferKind? {
        guard let folder = cards.first(where: { $0.id == cardID })?.url, !urls.isEmpty else { return nil }
        if optionKey { return .copy }
        return urls.allSatisfy { FileOperations.isSameVolume($0, folder) } ? .move : .copy
    }

    /// Moves or copies the dropped items into the folder of the card. Returns false when no item went into the folder.
    @discardableResult
    func drop(_ urls: [URL], on cardID: FolderCard.ID, optionKey: Bool) -> Bool {
        guard let kind = dropKind(for: urls, on: cardID, optionKey: optionKey) else { return false }
        return transfer(urls, to: cardID, kind: kind)
    }

    /// Moves or copies the items into the folder of the card. An item that is already in the folder does not move.
    /// A folder cannot go into itself. When a name is taken, the new item gets a free name.
    /// The last new item becomes the selected item. Returns false when no item went into the folder.
    @discardableResult
    func transfer(_ urls: [URL], to cardID: FolderCard.ID, kind: TransferKind) -> Bool {
        guard let folder = cards.first(where: { $0.id == cardID })?.url else { return false }
        commitRename()
        var moves: [(from: URL, to: URL)] = []
        var copies: [URL] = []
        for url in urls {
            if FileOperations.isFolder(folder, inOrEqualTo: url) {
                errorMessage = "The folder “\(url.lastPathComponent)” cannot go into itself."
            } else if kind == .copy {
                attempt { copies.append(try FileOperations.copy(url, into: folder)) }
            } else if !FileOperations.isItem(url, directlyIn: folder) {
                attempt { moves.append((from: url, to: try FileOperations.move(url, into: folder))) }
            }
        }
        if !moves.isEmpty { undoSteps.append(.move(moves)) }
        if !copies.isEmpty { undoSteps.append(.copy(copies)) }
        guard let last = copies.last ?? moves.last?.to else { return false }
        reload()
        select(itemNamed: last.lastPathComponent, in: cardID)
        return true
    }

    /// Reverses the last file operation: a rename, a new folder, a move to the Trash, a paste or a drop.
    /// The undo of a copy or of a new folder moves the new item to the Trash. Returns false when there is no operation to reverse.
    @discardableResult
    func undo() -> Bool {
        guard let step = undoSteps.popLast() else { return false }
        switch step {
        case .rename(let from, let to):
            if attempt({ try FileManager.default.moveItem(at: to, to: from) }) {
                moveCards(from: to, to: from)
            }
        case .move(let moves):
            for move in moves {
                attempt { try FileManager.default.moveItem(at: move.to, to: move.from) }
            }
        case .copy(let copies):
            for copy in copies {
                attempt { _ = try trash(copy) }
            }
        case .newFolder(let folder):
            attempt { _ = try trash(folder) }
        case .trash(let original, let trashed):
            attempt { try FileManager.default.moveItem(at: trashed, to: original) }
        }
        reload()
        return true
    }
}
