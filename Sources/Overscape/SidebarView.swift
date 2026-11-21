import SwiftUI
import UniformTypeIdentifiers

/// The window content: the sidebar with the workspaces and the canvas of the selected workspace.
struct MainView: View {
    let workspaces: WorkspacesModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: workspaces)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            // A new view identity for each workspace, so that no view state goes from one canvas to the next.
            CanvasView(model: workspaces.selected.canvas)
                .id(workspaces.selectedID)
                .navigationTitle(workspaces.selected.name)
                // The system background of the title bar starts 3 points to the left of the canvas.
                // Hide it. Show the canvas color and a separator line that have the same width as the canvas.
                .toolbarBackground(.hidden, for: .windowToolbar)
                .overlay(alignment: .top) { Divider() }
                .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        }
    }
}

struct SidebarView: View {
    let model: WorkspacesModel
    @State private var renamingID: Workspace.ID?
    @State private var draftName = ""
    @State private var pendingDelete: Workspace?
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        List(selection: selection) {
            Section("Workspaces") {
                ForEach(model.workspaces) { workspace in
                    row(for: workspace)
                        .tag(workspace.id)
                }
                Button(action: addWorkspace) {
                    Label("New Workspace", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .selectionDisabled()
            }
            // The favorites of the selected workspace.
            Section("Favorites") {
                ForEach(model.selected.favorites, id: \.path) { folder in
                    favoriteRow(for: folder)
                }
                if model.selected.favorites.isEmpty {
                    Text("Drag a folder here")
                        .foregroundStyle(.tertiary)
                        .selectionDisabled()
                }
            }
        }
        .listStyle(.sidebar)
        // A folder from Finder or from a card becomes a favorite.
        .dropDestination(for: URL.self) { urls, _ in model.addFavorites(urls) }
        .confirmationDialog(
            "Delete the workspace “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { workspace in
            Button("Delete", role: .destructive) { model.delete(workspace.id) }
        } message: { workspace in
            Text("The workspace has \(workspace.canvas.cards.count) open cards. The folders on disk do not change.")
        }
    }

    private var selection: Binding<Workspace.ID?> {
        Binding(get: { model.selectedID }, set: { if let id = $0 { model.select(id) } })
    }

    @ViewBuilder
    private func row(for workspace: Workspace) -> some View {
        HStack {
            Label {
                if renamingID == workspace.id {
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.plain)
                        .focused($isNameFieldFocused)
                        .onSubmit { commitRename() }
                        .onExitCommand { renamingID = nil }
                        .onChange(of: isNameFieldFocused) { _, focused in
                            if !focused { commitRename() }
                        }
                } else {
                    Text(workspace.name)
                }
            } icon: {
                Image(systemName: "rectangle.split.2x1")
            }
            Spacer()
            if workspace.id == model.selectedID && model.canDelete && renamingID != workspace.id {
                Button { requestDelete(workspace) } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete Workspace")
            }
        }
        .contentShape(Rectangle())
        // A tap gesture on the row stops the list selection, so the row selects itself.
        // The single tap is simultaneous with the double tap, so the selection does not wait for a second click.
        .onTapGesture(count: 2) { startRename(workspace) }
        .simultaneousGesture(TapGesture().onEnded { model.select(workspace.id) })
        .contextMenu {
            Button("Rename") { startRename(workspace) }
            Button("Delete", role: .destructive) { requestDelete(workspace) }
                .disabled(!model.canDelete)
        }
    }

    /// A click adds a card at the center of the canvas. A drag to the canvas adds a card at the drop position.
    private func favoriteRow(for folder: URL) -> some View {
        Label(folder.lastPathComponent.isEmpty ? folder.path : folder.lastPathComponent, systemImage: Self.symbol(for: folder))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { model.selected.canvas.addFolderAtCenter(folder) }
            .onDrag { FavoriteDrag.itemProvider(for: folder) }
            .contextMenu {
                Button("Remove from Favorites") { model.removeFavorite(folder) }
            }
            .selectionDisabled()
            .help(folder.path)
    }

    /// The standard folders have the same symbols as in the Finder sidebar.
    private static func symbol(for folder: URL) -> String {
        switch folder.path {
        case URL.homeDirectory.path: "house"
        case URL.desktopDirectory.path: "menubar.dock.rectangle"
        case URL.documentsDirectory.path: "doc"
        case URL.downloadsDirectory.path: "arrow.down.circle"
        default: "folder"
        }
    }

    private func addWorkspace() {
        let id = model.add()
        if let workspace = model.workspaces.first(where: { $0.id == id }) {
            startRename(workspace)
        }
    }

    private func startRename(_ workspace: Workspace) {
        draftName = workspace.name
        renamingID = workspace.id
        isNameFieldFocused = true
    }

    private func commitRename() {
        guard let id = renamingID else { return }
        model.rename(id, to: draftName)
        renamingID = nil
    }

    private func requestDelete(_ workspace: Workspace) {
        if model.needsDeleteConfirmation(workspace.id) {
            pendingDelete = workspace
        } else {
            model.delete(workspace.id)
        }
    }
}

/// A drag that starts at a favorite in the sidebar.
/// The drag has the folder path in a private type and no file URL. Thus a drop on a card or on a
/// different app cannot move the folder on disk. Only the canvas accepts the drag.
enum FavoriteDrag {
    static let type = UTType(exportedAs: "com.mxgrn.overscape.favorite")

    static func itemProvider(for folder: URL) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { completion in
            completion(Data(folder.path.utf8), nil)
            return nil
        }
        return provider
    }

    /// Gives the folder of a dropped favorite to `action` on the main actor.
    static func loadFolder(from provider: NSItemProvider, action: @escaping @MainActor (URL) -> Void) {
        _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
            guard let data, let path = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in action(URL(fileURLWithPath: path, isDirectory: true)) }
        }
    }
}
