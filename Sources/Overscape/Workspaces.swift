import Foundation
import Observation

/// A named canvas. Each workspace has its own cards, zoom and pan.
struct Workspace: Identifiable {
    let id: UUID
    var name: String
    let canvas: CanvasModel
}

/// The saved state of all workspaces.
struct WorkspacesSnapshot: Codable, Equatable {
    struct Workspace: Codable, Equatable {
        let id: UUID
        let name: String
        let canvas: CanvasSnapshot
    }

    var workspaces: [Workspace]
    var selectedID: UUID?
}

/// Reads and writes the workspaces snapshot as a JSON file.
enum WorkspacesFile {
    static var defaultURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Overscape", isDirectory: true)
            .appendingPathComponent("workspaces.json")
    }

    static func save(_ snapshot: WorkspacesSnapshot, to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }

    /// Returns nil when there is no file or the file is not valid.
    static func load(from url: URL = defaultURL) -> WorkspacesSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WorkspacesSnapshot.self, from: data)
    }
}

/// The list of workspaces and the selected workspace. There is always at least one workspace.
@MainActor
@Observable
final class WorkspacesModel {
    private(set) var workspaces: [Workspace]
    private(set) var selectedID: Workspace.ID

    init() {
        let first = Workspace(id: UUID(), name: "Workspace 1", canvas: CanvasModel())
        workspaces = [first]
        selectedID = first.id
    }

    var selected: Workspace {
        workspaces.first { $0.id == selectedID } ?? workspaces[0]
    }

    /// A workspace can be deleted only when it is not the last one.
    var canDelete: Bool { workspaces.count > 1 }

    var snapshot: WorkspacesSnapshot {
        WorkspacesSnapshot(
            workspaces: workspaces.map { .init(id: $0.id, name: $0.name, canvas: $0.canvas.snapshot) },
            selectedID: selectedID
        )
    }

    /// Replaces all workspaces with the saved state. A snapshot without workspaces changes nothing.
    func restore(_ snapshot: WorkspacesSnapshot) {
        guard !snapshot.workspaces.isEmpty else { return }
        workspaces = snapshot.workspaces.map { saved in
            let canvas = CanvasModel()
            canvas.restore(saved.canvas)
            return Workspace(id: saved.id, name: saved.name, canvas: canvas)
        }
        let ids = workspaces.map(\.id)
        selectedID = snapshot.selectedID.flatMap { ids.contains($0) ? $0 : nil } ?? ids[0]
    }

    /// Puts a canvas from a version without workspaces into the first workspace.
    func restore(legacyCanvas: CanvasSnapshot) {
        selected.canvas.restore(legacyCanvas)
    }

    func select(_ id: Workspace.ID) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    /// Adds an empty workspace with the next free name "Workspace N" and selects it.
    @discardableResult
    func add() -> Workspace.ID {
        let names = Set(workspaces.map(\.name))
        var number = workspaces.count + 1
        while names.contains("Workspace \(number)") { number += 1 }
        let workspace = Workspace(id: UUID(), name: "Workspace \(number)", canvas: CanvasModel())
        workspaces.append(workspace)
        selectedID = workspace.id
        return workspace.id
    }

    /// Changes the name. A name with only spaces is ignored.
    func rename(_ id: Workspace.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].name = trimmed
    }

    /// The user must confirm the delete of a workspace that has cards.
    func needsDeleteConfirmation(_ id: Workspace.ID) -> Bool {
        workspaces.first { $0.id == id }.map { !$0.canvas.cards.isEmpty } ?? false
    }

    /// Deletes the workspace. The last workspace is not deleted.
    /// When the selected workspace is deleted, the next workspace (or the previous one at the end) becomes selected.
    func delete(_ id: Workspace.ID) {
        guard canDelete, let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces.remove(at: index)
        if selectedID == id {
            selectedID = workspaces[min(index, workspaces.count - 1)].id
        }
    }
}
