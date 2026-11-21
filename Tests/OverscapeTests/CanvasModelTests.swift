import Foundation
import Testing
@testable import Overscape

@MainActor
struct CanvasModelTests {
    @Test func zoomKeepsThePointUnderTheAnchorInPlace() {
        let model = CanvasModel()
        model.pan(by: CGSize(width: 40, height: -10))
        let anchor = CGPoint(x: 300, y: 200)
        let before = model.canvasPoint(fromView: anchor)

        model.zoom(by: 2, around: anchor)

        #expect(model.zoom == 2)
        #expect(model.canvasPoint(fromView: anchor) == before)
    }

    @Test func aScrollFromEmptyCanvasPansAlsoWhenACardComesBelowTheCursor() throws {
        let root = try makeFolder(subfolders: ["a"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: CGPoint(x: 100, y: 100))
        let cursor = CGPoint(x: 50, y: 50)

        model.beginScroll(at: cursor)
        #expect(model.scroll(by: CGSize(width: -80, height: -80)))
        #expect(model.cards[0].frame.contains(model.canvasPoint(fromView: cursor)))

        #expect(model.scroll(by: CGSize(width: -10, height: 0)))
        #expect(model.pan == CGSize(width: -90, height: -80))
    }

    @Test func aScrollFromACardOrFromOutsideTheCanvasDoesNotPan() throws {
        let root = try makeFolder(subfolders: ["a"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: CGPoint(x: 100, y: 100))

        model.beginScroll(at: CGPoint(x: 110, y: 110))
        #expect(!model.scroll(by: CGSize(width: 0, height: 30)))

        model.beginScroll(at: nil)
        #expect(!model.scroll(by: CGSize(width: 0, height: 30)))

        #expect(model.pan == .zero)
    }

    @Test func childCardsKeepTheOrderOfTheirRows() throws {
        let root = try makeFolder(subfolders: ["a", "b", "c"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: CGPoint(x: 100, y: 100))
        let parent = model.cards[0]
        let rows = parent.entries.map(\.url)

        // Open the bottom row first, then the top row (it must go above),
        // then the middle row (no space, so the bottom card must move down).
        model.openChild(of: parent.id, folder: rows[2])
        model.openChild(of: parent.id, folder: rows[0])
        model.openChild(of: parent.id, folder: rows[1])
        model.openChild(of: parent.id, folder: rows[0])

        #expect(model.cards.count == 4)
        let children = try rows.map { row in try #require(model.cards.first { $0.url == row }) }
        #expect(children.allSatisfy { $0.position.x == 100 + CardLayout.defaultWidth + CardLayout.childSpacing })
        for (upper, lower) in zip(children, children.dropFirst()) {
            #expect(upper.position.y + upper.height + CardLayout.siblingSpacing <= lower.position.y)
        }
    }

    @Test func closeAlsoClosesChildCards() throws {
        let root = try makeFolder(subfolders: ["a"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        model.openChild(of: model.cards[0].id, folder: model.cards[0].entries[0].url)
        #expect(model.cards.count == 2)

        model.close(model.cards[0].id)

        #expect(model.cards.isEmpty)
    }

    @Test func restoreBringsBackTheCardTreeAndTheViewport() throws {
        let root = try makeFolder(subfolders: ["a"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: CGPoint(x: 100, y: 50))
        model.openChild(of: model.cards[0].id, folder: model.cards[0].entries[0].url)
        model.zoom(by: 2, around: CGPoint(x: 10, y: 20))
        model.setHovered(model.cards[0].id, true)
        model.setViewModeOfHoveredCard(.icons)
        model.resize(model.cards[1].id, edges: .bottom, from: model.cards[1].frame, by: CGSize(width: 0, height: 200))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try SnapshotStore.save(model.snapshot, to: file)

        let restored = CanvasModel()
        restored.restore(try #require(SnapshotStore.load(from: file)))

        #expect(restored.snapshot == model.snapshot)
        #expect(restored.connections.count == 1)
        #expect(restored.cards[0].viewMode == .icons)
        #expect(restored.cards[1].frame == model.cards[1].frame)
    }

    @Test func aSnapshotWithoutViewModesRestoresListMode() throws {
        let root = try makeFolder(subfolders: ["a"])
        defer { try? FileManager.default.removeItem(at: root) }
        let json = """
            {"cards":[{"id":"\(UUID().uuidString)","path":"\(root.path)","x":0,"y":0}],"zoom":1,"panX":0,"panY":0}
            """
        let snapshot = try JSONDecoder().decode(CanvasSnapshot.self, from: Data(json.utf8))

        let model = CanvasModel()
        model.restore(snapshot)

        #expect(model.cards.map(\.viewMode) == [.list])
        #expect(model.cards[0].width == CardLayout.defaultWidth)
        #expect(model.cards[0].fixedHeight == nil)
    }

    @Test func aCornerResizeMovesTwoEdgesAndKeepsTheOppositeEdges() throws {
        let root = try makeFolder(subfolders: ["a"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: CGPoint(x: 100, y: 100))
        let start = model.cards[0].frame

        model.resize(model.cards[0].id, edges: [.top, .left], from: start, by: CGSize(width: -50, height: -300))

        #expect(model.cards[0].frame == CGRect(
            x: start.minX - 50, y: start.minY - 300, width: start.width + 50, height: start.height + 300
        ))
    }

    @Test func aResizeStopsAtTheMinimumSize() throws {
        let root = try makeFolder(subfolders: ["a"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        let start = model.cards[0].frame

        model.resize(model.cards[0].id, edges: [.top, .left], from: start, by: CGSize(width: 1000, height: 1000))

        #expect(model.cards[0].frame == CGRect(
            x: start.maxX - CardLayout.minWidth, y: start.maxY - CardLayout.minHeight,
            width: CardLayout.minWidth, height: CardLayout.minHeight
        ))
    }

    @Test func aWidthResizeKeepsTheHeightFromTheContent() throws {
        let root = try makeFolder(subfolders: ["a", "b", "c", "d", "e"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        model.setHovered(model.cards[0].id, true)
        model.setViewModeOfHoveredCard(.icons)
        #expect(model.cards[0].iconColumns == 4)

        // 5 icons on one grid line need 5 cells of the minimum width.
        let width = 5 * CardLayout.iconMinCellWidth + 2 * CardLayout.gridPadding
        model.resize(model.cards[0].id, edges: .right, from: model.cards[0].frame,
                     by: CGSize(width: width - CardLayout.defaultWidth, height: 0))

        #expect(model.cards[0].iconColumns == 5)
        #expect(model.cards[0].fixedHeight == nil)
        #expect(model.cards[0].height == CardLayout.height(entryCount: 5, mode: .icons, width: width))
    }

    @Test func aChildCardOpensToTheRightOfAResizedParent() throws {
        let root = try makeFolder(subfolders: ["a"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        let parent = model.cards[0]
        model.resize(parent.id, edges: .right, from: parent.frame, by: CGSize(width: 100, height: 0))

        model.openChild(of: parent.id, folder: parent.entries[0].url)

        #expect(model.cards[1].position.x == model.cards[0].width + CardLayout.childSpacing)
        #expect(model.connections.map(\.start.x) == [model.cards[0].width])
    }

    @Test func viewModeKeysChangeOnlyTheHoveredCard() throws {
        let root = try makeFolder(subfolders: ["a"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root, root], at: .zero)

        #expect(!model.setViewModeOfHoveredCard(.icons))

        model.setHovered(model.cards[1].id, true)
        #expect(model.setViewModeOfHoveredCard(.icons))
        #expect(model.cards.map(\.viewMode) == [.list, .icons])
        #expect(model.cards[1].height == CardLayout.height(entryCount: 1, mode: .icons))

        model.setViewModeOfHoveredCard(.list)
        #expect(model.cards[1].viewMode == .list)

        model.setHovered(model.cards[1].id, false)
        #expect(!model.setViewModeOfHoveredCard(.icons))
    }

    @Test func inIconModeTheLineStartsLevelWithTheIcon() throws {
        let root = try makeFolder(subfolders: ["a", "b", "c", "d", "e"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: CGPoint(x: 100, y: 50))
        let parent = model.cards[0]
        model.setHovered(parent.id, true)
        model.setViewModeOfHoveredCard(.icons)

        // With 4 icons on each grid line, the fifth item is on the second line.
        model.openChild(of: parent.id, folder: parent.entries[4].url)

        let expectedY = 50 + CardLayout.contentTop(mode: .icons) + CardLayout.gridPadding + 1.5 * CardLayout.iconCellHeight
        #expect(model.connections.map(\.start.y) == [expectedY])
    }

    @Test func restoreSkipsAMissingFolderAndItsChildCards() throws {
        let root = try makeFolder(subfolders: ["a"])
        defer { try? FileManager.default.removeItem(at: root) }
        let other = try makeFolder(subfolders: ["b"])
        defer { try? FileManager.default.removeItem(at: other) }
        let model = CanvasModel()
        model.addFolders([root, other], at: .zero)
        model.openChild(of: model.cards[0].id, folder: model.cards[0].entries[0].url)
        let snapshot = model.snapshot
        try FileManager.default.removeItem(at: root)

        let restored = CanvasModel()
        restored.restore(snapshot)

        #expect(restored.cards.map(\.id) == [model.cards[1].id])
    }

    @Test func addFolderAtCenterPutsTheCardAtTheCenterOfTheVisibleCanvas() throws {
        let root = try makeFolder(subfolders: ["a"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.viewSize = CGSize(width: 800, height: 600)
        model.pan(by: CGSize(width: 100, height: 0))
        model.zoom(by: 2, around: .zero)

        model.addFolderAtCenter(root)
        model.addFolderAtCenter(root)

        let center = model.canvasPoint(fromView: CGPoint(x: 400, y: 300))
        let first = model.cards[0].frame
        #expect(CGPoint(x: first.midX, y: first.midY) == center)
        #expect(model.cards[1].position == CGPoint(x: first.minX + 30, y: first.minY + 30))
    }

    @Test func aDoubleClickOnAFolderShowsItInTheSameCardAndCommandUpBringsTheLinesBack() throws {
        let root = try makeFolder(subfolders: ["a/b"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        model.openChild(of: model.cards[0].id, folder: model.cards[0].entries[0].url)
        let card = model.cards[1]
        let subfolder = card.entries[0].url
        model.openChild(of: card.id, folder: subfolder)
        let child = model.cards[2]

        model.open(subfolder, in: card.id)
        model.reload()

        #expect(model.cards.map(\.url) == [model.cards[0].url, subfolder, subfolder])
        #expect(model.cards[1].position == card.position)
        #expect(model.connections.isEmpty)

        model.setHovered(card.id, true)
        model.perform(.showParentFolder)

        #expect(model.connections.map(\.id) == [card.id, child.id])
    }

    @Test func aCardKeepsItsHeightWhenItShowsADifferentFolder() throws {
        let root = try makeFolder(subfolders: ["a/b", "a/c"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        model.openChild(of: model.cards[0].id, folder: model.cards[0].entries[0].url)
        let heights = model.cards.map(\.height)

        // The first card gets more items and the second card gets fewer items.
        model.open(model.cards[0].entries[0].url, in: model.cards[0].id)
        model.open(model.cards[1].entries[0].url, in: model.cards[1].id)

        #expect(model.cards.map(\.entries.count) == [2, 0])
        #expect(model.cards.map(\.height) == heights)
    }

    @Test func aDoubleClickWithCommandOpensAFolderInAChildCard() throws {
        let root = try makeFolder(subfolders: ["a"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        let parent = model.cards[0]

        model.open(parent.entries[0].url, in: parent.id, inChildCard: true)

        #expect(model.cards.map(\.url) == [parent.url, parent.entries[0].url])
        #expect(model.cards[1].parentID == parent.id)
    }

    @Test func commandUpShowsTheParentFolderAndSelectsTheFolderFromBefore() throws {
        let root = try makeFolder(subfolders: ["a"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        let card = model.cards[0]
        let subfolder = card.entries[0].url
        model.open(subfolder, in: card.id)

        #expect(!model.perform(.showParentFolder))
        model.setHovered(card.id, true)
        #expect(model.perform(.showParentFolder))

        #expect(model.cards[0].entries.map(\.url) == [subfolder])
        #expect(model.selection == ItemRef(cardID: card.id, url: subfolder))
    }

    @Test func arrowKeysMoveTheSelectionInAList() throws {
        let root = try makeFolder(subfolders: ["a", "b", "c"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        let card = model.cards[0]
        let rows = card.entries.map(\.url)

        #expect(!model.perform(.moveSelection(.down)))

        model.setHovered(card.id, true)
        var selected: [URL?] = []
        for direction in [ArrowDirection.down, .down, .right, .up, .up] {
            #expect(model.perform(.moveSelection(direction)))
            selected.append(model.selection?.url)
        }
        #expect(selected == [rows[0], rows[1], rows[1], rows[0], rows[0]])

        model.clearSelection()
        model.perform(.moveSelection(.up))
        #expect(model.selection?.url == rows[2])
    }

    @Test func anArrowKeyMovesTheSelectionToTheCardUnderTheCursor() throws {
        let root = try makeFolder(subfolders: ["a", "b"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root, root], at: .zero)
        let rows = model.cards[0].entries.map(\.url)
        model.select(rows[1], in: model.cards[0].id)

        model.setHovered(model.cards[1].id, true)
        model.perform(.moveSelection(.down))

        #expect(model.selection == ItemRef(cardID: model.cards[1].id, url: rows[0]))
    }

    @Test func arrowKeysMoveTheSelectionInAGridOfIcons() throws {
        let root = try makeFolder(subfolders: ["a", "b", "c", "d", "e", "f"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        let card = model.cards[0]
        model.setHovered(card.id, true)
        model.setViewModeOfHoveredCard(.icons)

        // With 4 icons on each grid line, the second line has the items 4 and 5.
        var selected: [Int?] = []
        for direction in [ArrowDirection.left, .up, .up, .right, .right, .down, .down, .left, .left] {
            model.perform(.moveSelection(direction))
            selected.append(card.entries.firstIndex { $0.url == model.selection?.url })
        }
        #expect(selected == [5, 1, 1, 2, 3, 5, 5, 4, 3])
    }

    @Test func commandDownShowsTheSelectedFolderInTheSameCard() throws {
        let root = try makeFolder(subfolders: ["a"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        let subfolder = model.cards[0].entries[0].url

        #expect(!model.perform(.openSelection))
        model.select(subfolder, in: model.cards[0].id)
        #expect(model.perform(.openSelection))

        #expect(model.cards.map(\.url) == [subfolder])
    }

    private func makeFolder(subfolders: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for name in subfolders {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        return root
    }

    @Test func zoomStaysInRange() {
        let model = CanvasModel()

        model.zoom(by: 100, around: .zero)

        #expect(model.zoom == CanvasModel.zoomRange.upperBound)
    }
}
