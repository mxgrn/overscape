import AppKit
import Foundation
import Testing
@testable import Overscape

@MainActor
struct FileOperationsTests {
    @Test func renameChangesTheNameOnDiskAndKeepsTheChildCard() throws {
        let root = try makeFolder(items: ["a/"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        let parent = model.cards[0]
        model.openChild(of: parent.id, folder: parent.entries[0].url)

        model.select(parent.entries[0].url, in: parent.id)
        model.beginRename()
        model.renameDraft = "b"
        model.commitRename()

        #expect(model.cards[0].entries.map(\.name) == ["b"])
        #expect(model.selection?.url == model.cards[0].entries[0].url)
        #expect(model.cards[1].title == "b")
        #expect(model.connections.count == 1)

        model.undo()

        #expect(model.cards[0].entries.map(\.name) == ["a"])
        #expect(model.connections.count == 1)
    }

    @Test func renameToATakenNameGivesAnErrorAndChangesNothing() throws {
        let root = try makeFolder(items: ["a.txt", "b.txt"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        let card = model.cards[0]
        let item = try #require(card.entries.first { $0.name == "a.txt" })

        model.rename(ItemRef(cardID: card.id, url: item.url), to: "b.txt")

        #expect(model.errorMessage == "The name “b.txt” is already taken. Use a different name.")
        #expect(names(in: model.cards[0]) == ["a.txt", "b.txt"])
    }

    @Test func escapeKeepsTheOldName() throws {
        let root = try makeFolder(items: ["a.txt"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        model.select(model.cards[0].entries[0].url, in: model.cards[0].id)

        model.beginRename()
        model.renameDraft = "b.txt"
        model.cancelRename()

        #expect(model.renaming == nil)
        #expect(names(in: model.cards[0]) == ["a.txt"])
    }

    @Test func aClickOnADifferentItemKeepsTheNewName() throws {
        let root = try makeFolder(items: ["a.txt", "b.txt"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        let card = model.cards[0]
        let first = try #require(card.entries.first { $0.name == "a.txt" })
        let second = try #require(card.entries.first { $0.name == "b.txt" })

        model.select(first.url, in: card.id)
        model.beginRename()
        model.renameDraft = "c.txt"
        model.select(second.url, in: card.id)

        #expect(names(in: model.cards[0]) == ["b.txt", "c.txt"])
        #expect(model.selection?.url == second.url)
    }

    @Test func moveToTrashRemovesTheItemAndItsCardAndUndoPutsTheItemBack() throws {
        let root = try makeFolder(items: ["a/"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        let parent = model.cards[0]
        model.openChild(of: parent.id, folder: parent.entries[0].url)

        model.select(parent.entries[0].url, in: parent.id)
        model.trashSelection()

        #expect(model.cards.count == 1)
        #expect(model.cards[0].entries.isEmpty)
        #expect(model.selection == nil)

        model.undo()

        #expect(names(in: model.cards[0]) == ["a"])
    }

    @Test func pasteCopiesTheItemIntoTheCardUnderTheCursor() throws {
        let source = try makeFolder(items: ["notes.txt"])
        let target = try makeFolder(items: [])
        defer { [source, target].forEach { try? FileManager.default.removeItem(at: $0) } }
        let model = CanvasModel()
        model.pasteboard = .withUniqueName()
        defer { model.pasteboard.releaseGlobally() }
        model.addFolders([source, target], at: .zero)

        model.select(model.cards[0].entries[0].url, in: model.cards[0].id)
        model.copySelection()
        model.setHovered(model.cards[1].id, true)
        model.paste()

        #expect(names(in: model.cards[0]) == ["notes.txt"])
        #expect(names(in: model.cards[1]) == ["notes.txt"])
        #expect(model.selection == ItemRef(cardID: model.cards[1].id, url: model.cards[1].entries[0].url))
    }

    @Test func pasteInTheSameFolderMakesACopyWithANewNameAndUndoRemovesIt() throws {
        let root = try makeFolder(items: ["notes.txt"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.pasteboard = .withUniqueName()
        defer { model.pasteboard.releaseGlobally() }
        model.trash = { try FileManager.default.removeItem(at: $0); return nil }
        model.addFolders([root], at: .zero)
        let card = model.cards[0]

        model.select(card.entries[0].url, in: card.id)
        model.copySelection()
        model.setHovered(card.id, true)
        model.paste()
        model.paste()

        #expect(names(in: model.cards[0]) == ["notes copy 2.txt", "notes copy.txt", "notes.txt"])

        model.undo()

        #expect(names(in: model.cards[0]) == ["notes copy.txt", "notes.txt"])
    }

    @Test func pasteWithMoveTakesTheItemOutOfItsFolder() throws {
        let source = try makeFolder(items: ["notes.txt"])
        let target = try makeFolder(items: [])
        defer { [source, target].forEach { try? FileManager.default.removeItem(at: $0) } }
        let model = CanvasModel()
        model.pasteboard = .withUniqueName()
        defer { model.pasteboard.releaseGlobally() }
        model.addFolders([source, target], at: .zero)

        model.select(model.cards[0].entries[0].url, in: model.cards[0].id)
        model.copySelection()
        model.setHovered(model.cards[1].id, true)
        model.paste(move: true)

        #expect(model.cards[0].entries.isEmpty)
        #expect(names(in: model.cards[1]) == ["notes.txt"])
    }

    @Test func aDropMovesTheItemToTheOtherCardAndUndoMovesItBack() throws {
        let source = try makeFolder(items: ["notes.txt"])
        let target = try makeFolder(items: [])
        defer { [source, target].forEach { try? FileManager.default.removeItem(at: $0) } }
        let model = CanvasModel()
        model.addFolders([source, target], at: .zero)
        let item = model.cards[0].entries[0].url

        #expect(model.dropKind(for: [item], on: model.cards[1].id, optionKey: false) == .move)
        model.drop([item], on: model.cards[1].id, optionKey: false)

        #expect(model.cards[0].entries.isEmpty)
        #expect(names(in: model.cards[1]) == ["notes.txt"])

        model.undo()

        #expect(names(in: model.cards[0]) == ["notes.txt"])
        #expect(model.cards[1].entries.isEmpty)
    }

    @Test func aDropWithTheOptionKeyMakesACopy() throws {
        let source = try makeFolder(items: ["notes.txt"])
        let target = try makeFolder(items: [])
        defer { [source, target].forEach { try? FileManager.default.removeItem(at: $0) } }
        let model = CanvasModel()
        model.addFolders([source, target], at: .zero)
        let item = model.cards[0].entries[0].url

        model.drop([item], on: model.cards[1].id, optionKey: true)

        #expect(names(in: model.cards[0]) == ["notes.txt"])
        #expect(names(in: model.cards[1]) == ["notes.txt"])
    }

    @Test func aDropOnTheCardOfTheSameFolderChangesNothing() throws {
        let root = try makeFolder(items: ["notes.txt"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        let card = model.cards[0]

        #expect(!model.drop([card.entries[0].url], on: card.id, optionKey: false))

        #expect(names(in: model.cards[0]) == ["notes.txt"])
    }

    @Test func aMovedItemGetsAFreeNameWhenTheNameIsTaken() throws {
        let source = try makeFolder(items: ["notes.txt"])
        let target = try makeFolder(items: ["notes.txt"])
        defer { [source, target].forEach { try? FileManager.default.removeItem(at: $0) } }
        let model = CanvasModel()
        model.addFolders([source, target], at: .zero)

        model.drop([model.cards[0].entries[0].url], on: model.cards[1].id, optionKey: false)

        #expect(names(in: model.cards[1]) == ["notes 2.txt", "notes.txt"])
    }

    @Test func aFolderCannotGoIntoItself() throws {
        let root = try makeFolder(items: ["a/"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        let parent = model.cards[0]
        let folder = parent.entries[0].url
        model.openChild(of: parent.id, folder: folder)

        #expect(!model.drop([folder], on: model.cards[1].id, optionKey: false))

        #expect(model.errorMessage != nil)
        #expect(names(in: model.cards[0]) == ["a"])
    }

    @Test func aMovedFolderClosesItsCard() throws {
        let source = try makeFolder(items: ["a/"])
        let target = try makeFolder(items: [])
        defer { [source, target].forEach { try? FileManager.default.removeItem(at: $0) } }
        let model = CanvasModel()
        model.addFolders([source, target], at: .zero)
        let folder = model.cards[0].entries[0].url
        model.openChild(of: model.cards[0].id, folder: folder)

        model.drop([folder], on: model.cards[1].id, optionKey: false)

        #expect(model.cards.map(\.url) == [source, target])
    }

    @Test func reloadShowsNewFilesAndClosesTheCardOfADeletedFolder() throws {
        let root = try makeFolder(items: ["a/"])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CanvasModel()
        model.addFolders([root], at: .zero)
        let folder = model.cards[0].entries[0].url
        model.openChild(of: model.cards[0].id, folder: folder)

        try FileManager.default.removeItem(at: folder)
        try Data().write(to: root.appendingPathComponent("new.txt"))
        model.reload()

        #expect(model.cards.count == 1)
        #expect(names(in: model.cards[0]) == ["new.txt"])
    }

    @Test func aCopyOfAFolderWithADotInItsNameKeepsTheFullName() throws {
        let root = try makeFolder(items: ["v1.2/"])
        defer { try? FileManager.default.removeItem(at: root) }

        let copy = try FileOperations.copy(root.appendingPathComponent("v1.2"), into: root)

        #expect(copy.lastPathComponent == "v1.2 copy")
    }

    /// The names of the items in the card, in alphabetical order.
    private func names(in card: FolderCard) -> [String] {
        card.entries.map(\.name).sorted()
    }

    /// Makes a folder with the items. A name that ends with a slash makes a subfolder.
    private func makeFolder(items: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in items {
            let url = root.appendingPathComponent(name)
            if name.hasSuffix("/") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            } else {
                try Data().write(to: url)
            }
        }
        return root
    }
}
