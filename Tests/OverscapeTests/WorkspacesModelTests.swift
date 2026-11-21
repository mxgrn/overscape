import Foundation
import Testing
@testable import Overscape

@MainActor
struct WorkspacesModelTests {
    @Test func addSelectsANewEmptyWorkspaceWithTheNextFreeName() {
        let model = WorkspacesModel()
        model.rename(model.selectedID, to: "Workspace 2")

        let id = model.add()

        #expect(model.selectedID == id)
        #expect(model.workspaces.map(\.name) == ["Workspace 2", "Workspace 3"])
        #expect(model.selected.canvas.cards.isEmpty)
    }

    @Test func renameIgnoresAnEmptyName() {
        let model = WorkspacesModel()

        model.rename(model.selectedID, to: "  Photos ")
        model.rename(model.selectedID, to: "   ")

        #expect(model.selected.name == "Photos")
    }

    @Test func deleteSelectsTheNextWorkspaceAndKeepsTheLastOne() {
        let model = WorkspacesModel()
        let first = model.selectedID
        let second = model.add()
        model.select(first)

        model.delete(first)
        #expect(model.selectedID == second)

        model.delete(second)
        #expect(model.workspaces.map(\.id) == [second])
    }

    @Test func onlyAWorkspaceWithCardsNeedsDeleteConfirmation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = WorkspacesModel()
        let empty = model.add()
        model.workspaces[0].canvas.addFolders([folder], at: .zero)

        #expect(model.needsDeleteConfirmation(model.workspaces[0].id))
        #expect(!model.needsDeleteConfirmation(empty))
    }

    @Test func eachWorkspaceKeepsItsOwnCanvasAfterRestore() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = WorkspacesModel()
        model.selected.canvas.addFolders([folder], at: .zero)
        model.add()
        model.selected.canvas.zoom(by: 2, around: .zero)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try WorkspacesFile.save(model.snapshot, to: file)

        let restored = WorkspacesModel()
        restored.restore(try #require(WorkspacesFile.load(from: file)))

        #expect(restored.snapshot == model.snapshot)
        #expect(restored.workspaces.map(\.canvas.cards.count) == [1, 0])
        #expect(restored.selected.canvas.zoom == 2)
    }

    @Test func aLegacyCanvasGoesIntoTheFirstWorkspace() {
        let model = WorkspacesModel()

        model.restore(legacyCanvas: CanvasSnapshot(cards: [], zoom: 2, panX: 0, panY: 0))

        #expect(model.workspaces.count == 1)
        #expect(model.selected.canvas.zoom == 2)
    }

    @Test func addFavoritesIgnoresFilesAndFoldersThatAreAlreadyFavorites() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a.txt")
        try Data().write(to: file)
        let model = WorkspacesModel()

        #expect(model.addFavorites([folder, file]))
        #expect(!model.addFavorites([folder]))

        #expect(model.selected.favorites == Workspace.standardFavorites + [folder])
    }

    @Test func eachWorkspaceHasItsOwnFavorites() {
        let model = WorkspacesModel()
        let first = model.selectedID
        model.removeFavorite(.desktopDirectory)
        model.add()

        #expect(model.selected.favorites == Workspace.standardFavorites)
        model.select(first)
        #expect(model.selected.favorites == [.homeDirectory, .documentsDirectory, .downloadsDirectory])
    }

    @Test func restoreKeepsTheFavorites() {
        let model = WorkspacesModel()
        model.removeFavorite(.homeDirectory)

        let restored = WorkspacesModel()
        restored.restore(model.snapshot)

        #expect(restored.selected.favorites.map(\.path) == model.selected.favorites.map(\.path))
    }

    @Test func aFileFromAVersionWithoutFavoritesGetsTheStandardFavorites() throws {
        let json = #"{"workspaces":[{"id":"\#(UUID())","name":"Old","canvas":{"cards":[],"zoom":1,"panX":0,"panY":0}}]}"#
        let model = WorkspacesModel()
        model.removeFavorite(.homeDirectory)

        model.restore(try JSONDecoder().decode(WorkspacesSnapshot.self, from: Data(json.utf8)))

        #expect(model.selected.favorites == Workspace.standardFavorites)
    }
}
