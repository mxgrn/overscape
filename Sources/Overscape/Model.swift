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

    func itemCenterY(index: Int) -> CGFloat {
        CardLayout.itemCenterY(index: index, entryCount: entries.count, mode: viewMode, scrollOffset: scrollOffset)
    }

    var title: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
    var height: CGFloat { CardLayout.height(entryCount: entries.count, mode: viewMode) }
}

/// Card sizes in canvas points. The card view and the model both use them.
enum CardLayout {
    static let width: CGFloat = 490
    static let headerHeight: CGFloat = 32
    static let columnHeaderHeight: CGFloat = 24
    static let dividerHeight: CGFloat = 1
    static let rowHeight: CGFloat = 27
    static let maxListHeight: CGFloat = 640
    /// Horizontal space between a card and the cards opened from it.
    static let childSpacing: CGFloat = 60
    /// Vertical space between cards opened from the same card.
    static let siblingSpacing: CGFloat = 20

    /// Icon mode: the size of one icon, as in Finder.
    static let iconSize: CGFloat = 64
    static let iconColumns = 4
    static let gridPadding: CGFloat = 10
    /// Icon mode: the height of one cell (icon, space and a name of two lines).
    static let iconCellHeight: CGFloat = 108
    static var iconCellWidth: CGFloat { (width - 2 * gridPadding) / CGFloat(iconColumns) }

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

    static func iconRowCount(entryCount: Int) -> Int {
        (max(entryCount, 1) + iconColumns - 1) / iconColumns
    }

    static func gridHeight(entryCount: Int) -> CGFloat {
        min(CGFloat(iconRowCount(entryCount: entryCount)) * iconCellHeight + 2 * gridPadding, maxListHeight)
    }

    /// The height of the item area. It scrolls when the items need more space.
    static func contentHeight(entryCount: Int, mode: CardViewMode) -> CGFloat {
        switch mode {
        case .list: listHeight(entryCount: entryCount)
        case .icons: gridHeight(entryCount: entryCount)
        }
    }

    static func height(entryCount: Int, mode: CardViewMode = .list) -> CGFloat {
        contentTop(mode: mode) + contentHeight(entryCount: entryCount, mode: mode)
    }

    /// The vertical center of an item (a row or an icon cell), from the top of the card.
    /// When the item is scrolled out of view, the value stops at the top or bottom edge of the item area.
    static func itemCenterY(index: Int, entryCount: Int, mode: CardViewMode, scrollOffset: CGFloat) -> CGFloat {
        let top = contentTop(mode: mode)
        let center: CGFloat
        switch mode {
        case .list:
            center = (CGFloat(index) + 0.5) * rowHeight
        case .icons:
            center = gridPadding + (CGFloat(index / iconColumns) + 0.5) * iconCellHeight
        }
        let y = top + scrollOffset + center
        return min(max(y, top), top + contentHeight(entryCount: entryCount, mode: mode))
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

    static let zoomRange: ClosedRange<CGFloat> = 0.25...3

    var snapshot: CanvasSnapshot {
        CanvasSnapshot(
            cards: cards.map {
                .init(id: $0.id, path: $0.url.path, x: $0.position.x, y: $0.position.y, parentID: $0.parentID, viewMode: $0.viewMode)
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
                viewMode: card.viewMode ?? .list
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
            position: CGPoint(x: parent.position.x + CardLayout.width + CardLayout.childSpacing, y: y),
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
                start: CGPoint(x: parent.position.x + CardLayout.width, y: parent.position.y + rowY),
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
