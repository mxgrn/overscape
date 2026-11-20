# Overscape

Overscape is a macOS app that shows folders as cards on an infinite canvas.
You drag a folder from Finder onto the canvas. The app shows the folder as a card that lists its files.
When you double-click a subfolder in a card, a child card opens to the right, with a curved line that connects the two cards.
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
| `Sources/Overscape/OverscapeApp.swift` | App entry point. The `AppDelegate` makes the SwiftPM executable a regular app with a Dock icon. It owns the `CanvasModel`, restores it at the start and saves it when the app quits. |
| `Sources/Overscape/Model.swift` | All state and logic: `FileEntry`, `FolderCard`, `CardLayout`, `Connection`, `FolderLoader`, `CanvasSnapshot`, `SnapshotStore`, `CanvasModel`. |
| `Sources/Overscape/CanvasView.swift` | The canvas: dot grid, connector lines, cards, drop target, zoom and pan transform. |
| `Sources/Overscape/CanvasEventView.swift` | An AppKit `NSView` behind the cards. It handles pinch, drag and cursor move events on the canvas. |
| `Sources/Overscape/FolderCardView.swift` | One card: header, column headers, file list, row selection, double-click, drag to move. |
| `Tests/OverscapeTests/` | Tests for `FolderLoader`, `CanvasModel` and save and restore. |

## Architecture

- `CanvasModel` is the single source of truth. It is `@MainActor` and `@Observable`. Views read from it and call its functions. Views do not keep canvas state.
- Keep logic in the model, not in views. Then you can test it without UI. Each new behavior in the model must have a test.
- **Coordinates.** Cards have positions in *canvas points*. The viewport maps a canvas point `p` to the view point `p * zoom + pan`. Use `canvasPoint(fromView:)` to convert in the other direction. Mouse movement from gestures is in screen points: divide it by `zoom` before you apply it to a card.
- **Card sizes.** `CardLayout` holds all card sizes. The view and the model both use it. The model must know row positions to place child cards and to draw connector lines. If you change the card layout in the view, change `CardLayout` too.
- **Scroll position.** Each card reports the scroll offset of its file list to the model (`setScrollOffset`). The model needs it so that connector lines start at the correct row.
- **Card drag.** A card drag changes the card position in the model during the drag, not only at the end. This makes the connector lines follow the card.

## Behavior

### Canvas

- At the start, the canvas is empty and shows a dot grid with the text "Drag a folder here".
- A drop of one or more folders makes one card for each folder, near the cursor. Items that are not folders are ignored.
- A trackpad pinch zooms from 25% to 300%. The point under the cursor stays in place. Pinch works everywhere in the window, also on top of a card. A local `NSEvent` monitor catches it.
- A drag on empty canvas moves (pans) the canvas.
- A two-finger scroll or the mouse wheel on empty canvas does nothing.
- When you hold the Control key and move the cursor, the canvas moves with the cursor. This works everywhere in the window, also on top of a card. A local `NSEvent` monitor catches it.
- The dot grid moves and scales with the canvas. When the dots are too close together, they are hidden.

### Save and restore

- The app has one window, so there is one canvas.
- When the app quits, it saves the open cards (root and child cards), their positions, and the zoom and pan. The file is `~/Library/Application Support/Overscape/canvas.json`.
- At the start, the app restores the saved canvas. It reads the file lists from disk again.
- If a saved folder does not exist, its card and all cards opened from it are not restored.
- The app saves only on a normal quit. A crash or a force quit loses the changes since the last start.
- The scroll offset of the file lists and the selected rows are not saved.

### Cards

- A header with the folder icon, the folder name, the number of items and a close (×) button. Drag the header to move the card.
- The columns are Name, Size and Date Modified. Dates use the format `dd.MM.yy, HH:mm`. Folders show `--` as the size.
- Items are sorted newest first. Hidden files are not shown.
- A single click selects a row. Rows that have an open child card stay highlighted.
- When the mouse is on a card, the card border becomes thicker and uses the full accent color.
- The list scrolls when it is taller than `CardLayout.maxListHeight`.

### Child cards

- A double-click on a subfolder row opens a child card to the right of the parent. A double-click on a file does nothing.
- A parent can have many child cards. A subfolder cannot have two open cards from the same parent. A second double-click brings the open card to the front.
- Child cards stay in the same vertical order as their rows in the parent, so that the connector lines do not cross. A new card starts level with its row. It stays below the card for the row above it and above the card for the row below it. If there is not enough space, the sibling cards below it move down.
- A curved line connects the parent row to the header of the child card. If the row scrolls out of view, the line starts at the top or bottom edge of the list.
- When you close a card, all cards that were opened from it also close.

## Known limits and open questions

- A scroll on top of a card moves the file list in that card, not the canvas. The wanted behavior is not decided yet.
- It is not decided if closing a card must also close its child cards. At the moment, it does.
- When sibling cards move down, the cards opened from them do not move. Lines further down the tree can then cross.
- Child card order uses the row order, not the current card positions. If you drag a child card out of order, a new card can overlap it.

## Conventions

- Write comments and docs in ASD-STE100 Simplified Technical English.
- Keep tests short and realistic. Set up only the data that the test checks.
- In tests, get file URLs from `card.entries`. Do not build them from the temporary directory path: on macOS that path is a symlink (`/var` to `/private/var`), so the URLs do not compare equal.
- Run `swift build` and `swift test` after each change. Do not leave compiler warnings.
- In commit messages, describe the change in one short line.
