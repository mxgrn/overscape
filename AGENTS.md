# Overscape

Overscape is a macOS app that shows folders as cards on an infinite canvas.
You drag a folder from Finder onto the canvas. The app shows the folder as a card that lists its files.
When you double-click a subfolder in a card with the Command key, a child card opens to the right, with a curved line that connects the two cards.
The result is a tree of folders that you can see and move around, like a mind map of the file system.

## Tech stack

- Swift 6, SwiftUI, and a small amount of AppKit.
- A Swift Package (`Package.swift`). There is no Xcode project.
- Minimum platform: macOS 14.
- Tests use Swift Testing (`import Testing`), not XCTest.

## Commands

```bash
swift build          # Build the app.
swift test           # Run all tests.
swift run            # Build and start the app.
```

The executable is at `.build/debug/Overscape`. When the last window closes, the app quits.

## Source files

| File | Purpose |
| --- | --- |
| `Sources/Overscape/OverscapeApp.swift` | App entry point. The `AppDelegate` makes the SwiftPM executable a regular app with a Dock icon (`AppIcon`). It owns the `WorkspacesModel`, restores it at the start and saves it when the app quits. |
| `Sources/Overscape/Model.swift` | All state and logic: `FileEntry`, `FolderCard`, `CardLayout`, `Connection`, `FolderLoader`, `CanvasSnapshot`, `SnapshotStore`, `ItemRef`, `CanvasCommand`, `UndoStep`, `CanvasModel`. |
| `Sources/Overscape/FileOperations.swift` | `FileOperations` (copy, move and Trash on disk, free names, the volume check) and `FolderWatcher` (reports changes in a folder). |
| `Sources/Overscape/Workspaces.swift` | `Workspace`, `WorkspacesSnapshot`, `WorkspacesFile`, `WorkspacesModel`: the list of workspaces, each with its own `CanvasModel` and its own favorites. |
| `Sources/Overscape/SidebarView.swift` | `MainView` (sidebar and canvas in a `NavigationSplitView`), `SidebarView` (the list of workspaces and the favorites) and `FavoriteDrag` (the drag of a favorite). |
| `Sources/Overscape/CanvasView.swift` | The canvas: dot grid, connector lines, cards, drop target, zoom and pan transform. |
| `Sources/Overscape/CanvasEventView.swift` | An AppKit `NSView` behind the cards. It handles pinch, scroll, click and drag events on the canvas and changes keys into `CanvasCommand` values. |
| `Sources/Overscape/FolderCardView.swift` | One card: header, column headers, file list, row selection, the name field for a rename, double-click, drag to move, drag and drop of items. |
| `Sources/Overscape/Resources/AppIcon.png` | The app icon, 1024 × 1024 pixels. It is a package resource. The app sets it as the Dock icon at the start. |
| `Assets/AppIcon.svg` | The source of the app icon. It is not part of the build. |
| `Tests/OverscapeTests/` | Tests for `FolderLoader`, `CanvasModel`, `WorkspacesModel`, save and restore, and the file operations. |

## Architecture

- `WorkspacesModel` holds the workspaces. Each workspace has its own `CanvasModel`. A `CanvasModel` is the single source of truth for one canvas. Both are `@MainActor` and `@Observable`. Views read from it and call its functions. Views do not keep canvas state.
- Keep logic in the model, not in views. Then you can test it without UI. Each new behavior in the model must have a test.
- **Coordinates.** Cards have positions in *canvas points*. The viewport maps a canvas point `p` to the view point `p * zoom + pan`. Use `canvasPoint(fromView:)` to convert in the other direction. Mouse movement from gestures is in screen points: divide it by `zoom` before you apply it to a card.
- **Card sizes.** `CardLayout` holds all card sizes. The view and the model both use it. The model must know row positions to place child cards and to draw connector lines. If you change the card layout in the view, change `CardLayout` too.
- **Scroll position.** Each card reports the scroll offset of its file list to the model (`setScrollOffset`). The model needs it so that connector lines start at the correct row.
- **Card drag.** A card drag changes the card position in the model during the drag, not only at the end. This makes the connector lines follow the card.
- **Selection and rename.** The model holds the selected item (`selection`), the item that the user renames (`renaming`) and the text in the name field (`renameDraft`). The keyboard commands need them.
- **File operations.** The model does all file operations (`rename`, `trashSelection`, `copySelection`, `paste`, `drop`, `undo`). After each operation it calls `reload`, which reads the file lists of all cards again. When an operation fails, the model sets `errorMessage` and the canvas shows an alert.
- **Double-click.** The card view sends each double-click to the model (`open`), with the state of the Command key. The model makes the decision: open the file, show the folder in the same card, or open a child card.
- **Keyboard commands.** `CanvasEventView` changes a key into a `CanvasCommand` and the model does it (`perform`). While a text field has the focus, the keys go to the text field.

## Behavior

### Canvas

- At the start, the canvas is empty and shows a dot grid with the text "Drag a folder here".
- A drop of one or more folders makes one card for each folder, near the cursor. Items that are not folders are ignored.
- A trackpad pinch zooms from 25% to 300%. The point under the cursor stays in place. Pinch works everywhere in the window, also on top of a card. A local `NSEvent` monitor catches it.
- A drag on empty canvas moves (pans) the canvas.
- A two-finger scroll that starts on empty canvas moves (pans) the canvas. The pan continues until the scroll and its momentum end, also when a card moves below the cursor. A local `NSEvent` monitor catches it.
- A two-finger scroll that starts on a card does not pan the canvas. It scrolls the file list of that card. The model makes this decision at the start of each scroll (`beginScroll`), from the card frames.
- The mouse wheel on empty canvas does nothing.
- The dot grid moves and scales with the canvas. When the dots are too close together, they are hidden.

### Workspaces

- The window has a sidebar with a "Workspaces" section. Each workspace is a separate canvas with its own cards, zoom and pan.
- A click on a workspace shows its canvas. The window title is the workspace name.
- "New Workspace" adds an empty workspace with the next free name "Workspace N", selects it and starts the rename.
- A double-click on a workspace (or "Rename" in the context menu) starts the rename. Return or a click outside keeps the new name. Escape cancels. A name with only spaces is ignored.
- The × button on the selected workspace (or "Delete" in the context menu) deletes it. If the workspace has cards, the app asks for confirmation first. The folders on disk do not change.
- There is always at least one workspace. The last workspace cannot be deleted.

### Favorites

- The sidebar has a "Favorites" section below the workspaces. It shows the favorite folders of the selected workspace. Each workspace has its own favorites.
- A new workspace starts with the standard favorites: Home, Desktop, Documents and Downloads.
- A click on a favorite adds a card for the folder at the center of the visible canvas (`addFolderAtCenter`). The canvas view reports its size to the model (`viewSize`). If a card is already at that position, the new card goes 30 points down and to the right.
- A drag of a favorite to the canvas adds a card at the drop position.
- The drag of a favorite has the folder path in a private type (`FavoriteDrag`) and no file URL. Thus a drop on a card or on a different app cannot move the folder on disk.
- To add a favorite, drag a folder to the sidebar: from Finder, a folder row or icon in a card, or the folder icon in a card header. The folder goes to the end of the list. Items that are not folders and folders that are already favorites are ignored.
- "Remove from Favorites" in the context menu removes a favorite. The folder on disk does not change.
- A favorite whose folder does not exist stays in the list. A click on it does nothing.

### Save and restore

- The app has one window, so there is one set of workspaces.
- When the app quits, it saves all workspaces (their names, the selected workspace, and for each workspace the favorites, the open cards (root and child cards), their positions, their sizes, their view modes, and the zoom and pan). The file is `~/Library/Application Support/Overscape/workspaces.json`.
- If there is no `workspaces.json`, the app reads `canvas.json` from a version without workspaces into the first workspace. The app does not change or delete `canvas.json`.
- At the start, the app restores the saved canvas. It reads the file lists from disk again.
- If a saved folder does not exist, its card and all cards opened from it are not restored.
- The app saves only on a normal quit. A crash or a force quit loses the changes since the last start.
- The scroll offset of the file lists and the selected rows are not saved.
- A saved file from a version without favorites restores each workspace with the standard favorites.
- A saved file from a version without view modes restores all cards in list mode.
- A saved file from a version without resize restores all cards with the default width and the height from the content.

### Cards

- A header with the folder icon, the folder name, the number of items and a close (×) button. Drag the header to move the card. A drag that starts on the folder icon drags the folder itself, as a row does.
- The columns are Name, Size and Date Modified. Dates use the format `dd.MM.yy, HH:mm`. Folders show `--` as the size.
- Items are sorted newest first. Hidden files are not shown.
- A single click selects a row. Rows that have an open child card are not highlighted. Only the selected row is highlighted.
- The canvas has not more than one selected item. A click on a row in a different card moves the selection to that card. A click on empty canvas removes the selection.
- When the mouse is on a card, the card border becomes thicker and uses the full accent color.
- The list scrolls when it is taller than `CardLayout.maxListHeight`.
- Escape closes the card under the cursor (`hoveredCardID`), as the close (×) button does. If no card is under the cursor, the key does nothing. During a rename, Escape cancels the rename and the card stays open.

### Arrow keys

- The arrow keys move the selection in the card under the cursor (`hoveredCardID`), as in Finder. If no card is under the cursor, the keys do nothing.
- In list mode, Up and Down select the row above or below. Left and Right do nothing.
- In icon mode, the four keys select the adjacent icon. Left and Right continue on the line above or below. When the last line is shorter, Down from the line above it selects the last icon.
- If the card has no selected item, Down and Right select the first item, and Up and Left select the last item. This also applies when the selected item is in a different card: the selection moves to the card under the cursor.
- At the first or the last item, the selection does not change.
- The item area scrolls to show the selected item. The card view does this (`showsSelection`), also after a click on an item that is not fully in view.

### File operations

The keys are the same as in Finder. They operate on the selected item. There is no multi-selection.

- **Rename.** Return starts the rename of the selected item. The name field shows the full name, with the name selected but not the extension. Return keeps the new name. Escape cancels. A click on a different item or on empty canvas also keeps the new name. A name with only spaces is ignored. A name cannot start with a dot or contain a slash. If the name is taken, an alert shows and the name does not change.
- When a folder gets a new name, the open cards for that folder and for the folders in it stay open and get the new path.
- **Delete.** Command-Delete moves the selected item to the Trash. There is no confirmation.
- **Copy and paste.** Command-C puts the selected item on the system pasteboard. Command-V copies the files on the pasteboard into the folder of the card under the cursor (`hoveredCardID`). Command-Option-V moves them instead. Files that were copied in Finder can be pasted, and Finder can paste files that were copied here.
- **Drag and drop.** Drag a row or an icon to a different card to put the item into the folder of that card. The Finder rule applies: a move on the same volume, a copy between different volumes. With the Option key, the drop always makes a copy. The target card shows a stronger border during the drag.
- Files and folders that are dragged from Finder onto a card go into the folder of that card, with the same rule. A folder that is dropped on empty canvas makes a new card, also when the drag starts in a card.
- A row or an icon can be dragged to Finder or to a different app. The target app then does the move or the copy.
- An item that is already in the target folder does not move. A folder cannot go into itself.
- **Name conflicts.** When the name is taken in the target folder, the new item gets a free name and no item is replaced: "a copy.txt", "a copy 2.txt" for a copy and "a 2.txt", "a 3.txt" for a move.
- After a paste or a drop, the new item is the selected item.
- **Undo.** Command-Z reverses the last file operation in the workspace: a rename, a move to the Trash, a paste or a drop. The undo of a copy moves the copy to the Trash. Each workspace has its own list of operations. The list is not saved. There is no redo.
- When a folder is moved or goes to the Trash, the cards for that folder and the cards opened from them close. An undo does not open them again.

### Live update

- Each card watches its folder (`FolderWatcher`). When an item is added, removed or renamed, in this app or in a different app, the model reads the file lists again (`reload`).
- A card whose folder does not exist closes. The cards opened from a closed card also close.
- A change of only the size or the date of a file does not start an update.
- When a workspace shows, its file lists are read again.

### Resize

- Drag any of the 4 edges or the 4 corners of a card to resize it. The opposite edges stay in place. The cursor changes to a resize cursor on the edges and corners. On macOS 14, the corners show a crosshair cursor, because macOS 14 has no public diagonal resize cursor.
- The resize area is half inside and half outside the card border.
- A card cannot become smaller than `CardLayout.minWidth` and `CardLayout.minHeight`.
- At the start, the height of a card comes from its content. When you move the top or the bottom edge, or when the card shows a different folder, the card gets a fixed height. If the content is shorter, the card shows empty space. If the content is taller, the list scrolls. A change of the width only keeps the height from the content.
- In icon mode, the number of icons on each line changes with the card width. Each cell is at least `CardLayout.iconMinCellWidth` wide.
- A resize does not move the child cards.

### View modes

- A card has two view modes, as in Finder: list (the default) and icons.
- Command-1 sets icon mode and Command-2 sets list mode for the card under the cursor. The model knows this card (`hoveredCardID`). If no card is under the cursor, the keys do nothing. A local `NSEvent` monitor catches the keys.
- Icon mode shows a grid of 64-point icons with the names below. With the default width, there are 4 icons on each line. It has no column headers. The card keeps its width. The grid scrolls when it is taller than `CardLayout.maxListHeight`.
- In icon mode, a single click selects an icon. A double-click does the same as in list mode. Icons that have an open child card are not highlighted.
- In icon mode, the connector line starts at the right edge of the card, level with the line of icons.

### Open and navigate

A double-click operates as in Finder.

- A double-click on a file opens the file in its default app. A package (an app, for example) opens as a file. If the file does not open, an alert shows.
- A double-click on a folder shows that folder in the same card. The card keeps its position, its size and its view mode. The items start at the top.
- When a card shows a different folder (a double-click, Command-Down or Command-Up), the card gets its height at that time as a fixed height. Thus the card does not become smaller when the new folder has fewer items, and it does not become taller when the new folder has more items. If the content is taller, the list scrolls.
- Command-Down opens the selected item, as a double-click does. The selected item can be in a card that is not under the cursor. If no item is selected, the key does nothing.
- Command-Up shows the parent folder in the card under the cursor (`hoveredCardID`) and selects the folder that the card showed before. If no card is under the cursor, or the card shows the top folder of the disk, the key does nothing.
- When a card shows a different folder, the card that it was opened from and the cards that were opened from it stay open. The cards stay related (`parentID`), but a connector line shows only while the folder of the child card is an item in the parent card. Thus the lines go when a card shows a different folder, and the lines come back when the card shows the initial folder again.
- There is no history. A card cannot go back or forward.

### Child cards

- A double-click with the Command key on a subfolder opens a child card to the right of the parent. A double-click with the Command key on a file does nothing.
- A parent can have many child cards. A subfolder cannot have two open cards from the same parent. A second double-click with the Command key brings the open card to the front.
- Child cards stay in the same vertical order as their rows in the parent, so that the connector lines do not cross. A new card starts level with its row. It stays below the card for the row above it and above the card for the row below it. If there is not enough space, the sibling cards below it move down.
- A curved line connects the parent row to the header of the child card. If the row scrolls out of view, the line starts at the top or bottom edge of the list.
- When you close a card, all cards that were opened from it also close, also the cards that have no line at that time.

## Known limits and open questions

- It is not decided if closing a card must also close its child cards. At the moment, it does.
- When a card changes its view mode, its height changes (if it has no fixed height). A resize also changes the height. Its child cards do not move, so they can overlap or the lines can cross.
- When sibling cards move down, the cards opened from them do not move. Lines further down the tree can then cross.
- Child card order uses the row order, not the current card positions. If you drag a child card out of order, a new card can overlap it.
- When the number of items in a card changes (a file operation or a live update), its height changes (if it has no fixed height). The other cards do not move, so cards can overlap.
- A folder that gets a new name in a different app is a removed folder and a new folder for the live update. Its cards close.
- An item cannot be dropped on a folder row to put it into that subfolder. The drop always goes into the folder of the card.
- The file commands are not in the menu bar. The Edit menu items stay disabled, but the keys work.
- The favorites cannot be put in a different order.
- When the folder of a card gets a new name, the scroll position of that card goes back to the top.
- While a child card shows a different folder, its row in the parent card is free and a second child card can open from that row. When the first card shows the initial folder again, the row has two lines.
- When a card shows a different folder, the cards opened from it do not move.
- Undo can fail when a different operation changed the same items after the operation. An alert then shows.

## Conventions

- Write comments and docs in ASD-STE100 Simplified Technical English.
- Keep tests short and realistic. Set up only the data that the test checks.
- In tests, get file URLs from `card.entries`. Do not build them from the temporary directory path: on macOS that path is a symlink (`/var` to `/private/var`), so the URLs do not compare equal.
- In tests for copy and paste, set `model.pasteboard` to a pasteboard with a unique name, so that the tests do not change the system pasteboard.
- A test must not leave items in the Trash of the user. A test that moves an item to the Trash must put it back with `undo`, or set `model.trash` to a function that removes the item.
- Run `swift build` and `swift test` after each change. Do not leave compiler warnings.
- After a change to `Assets/AppIcon.svg`, render it again to `Sources/Overscape/Resources/AppIcon.png` at 1024 × 1024 pixels with a transparent background. Use a renderer that supports SVG filters, for example headless Chrome.
- In commit messages, describe the change in one short line.
