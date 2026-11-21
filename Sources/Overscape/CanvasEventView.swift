import AppKit
import Quartz
import SwiftUI

/// An AppKit view behind the cards that turns raw input into canvas navigation:
/// - a pinch zooms around the cursor, or changes the icon size of the card under the cursor,
/// - a mouse drag on empty canvas pans,
/// - a two-finger scroll that starts on empty canvas pans,
/// - a two-finger scroll with the Control key pans, also when it starts on a card,
/// - a click on empty canvas removes the selection,
/// - the keys of Finder become canvas commands (arrow keys, view modes, open, Quick Look, parent folder, rename,
///   new folder, Trash, copy, paste, undo).
struct CanvasEventView: NSViewRepresentable {
    var onPan: (CGSize) -> Void
    /// The start of a two-finger scroll. The location is nil when the scroll starts outside the canvas.
    /// The second value is the state of the Control key.
    var onScrollBegan: (CGPoint?, Bool) -> Void
    /// Returns false when the scroll does not pan the canvas. The event then continues.
    var onScroll: (CGSize) -> Bool
    /// The start of a pinch, with the state of the Control key.
    var onMagnifyBegan: (Bool) -> Void
    var onMagnify: (_ factor: CGFloat, _ location: CGPoint) -> Void
    /// A mouse click on empty canvas.
    var onMouseDown: () -> Void
    /// Returns false when the command had no effect. The event then continues.
    var onCommand: (CanvasCommand) -> Bool

    func makeNSView(context: Context) -> EventNSView {
        let view = EventNSView()
        view.onPan = onPan
        view.onScrollBegan = onScrollBegan
        view.onScroll = onScroll
        view.onMagnifyBegan = onMagnifyBegan
        view.onMagnify = onMagnify
        view.onMouseDown = onMouseDown
        view.onCommand = onCommand
        return view
    }

    func updateNSView(_ view: EventNSView, context: Context) {
        view.onPan = onPan
        view.onScrollBegan = onScrollBegan
        view.onScroll = onScroll
        view.onMagnifyBegan = onMagnifyBegan
        view.onMagnify = onMagnify
        view.onMouseDown = onMouseDown
        view.onCommand = onCommand
    }

    final class EventNSView: NSView {
        var onPan: (CGSize) -> Void = { _ in }
        var onScrollBegan: (CGPoint?, Bool) -> Void = { _, _ in }
        var onScroll: (CGSize) -> Bool = { _ in false }
        var onMagnifyBegan: (Bool) -> Void = { _ in }
        var onMagnify: (CGFloat, CGPoint) -> Void = { _, _ in }
        var onMouseDown: () -> Void = {}
        var onCommand: (CanvasCommand) -> Bool = { _ in false }
        private var magnifyMonitor: Any?
        private var scrollMonitor: Any?
        private var keyMonitor: Any?

        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            // A pinch over a card goes to the card's scroll view, not to this view.
            // A local monitor sees every pinch in the window, so the pinch works everywhere.
            magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let location = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(location) else { return event }
                // The decision from the start of the pinch stays until the pinch ends.
                if event.phase.contains(.began) {
                    self.onMagnifyBegan(event.modifierFlags.contains(.control))
                }
                self.onMagnify(1 + event.magnification, location)
                return nil
            }
            // A scroll over a card goes to the card's scroll view, not to this view.
            // A local monitor sees every scroll in the window. Thus a pan that starts on
            // empty canvas can continue when a card moves below the cursor.
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                // A mouse wheel has no phases. It does not pan the canvas.
                guard !event.phase.isEmpty || !event.momentumPhase.isEmpty else { return event }
                if event.phase.contains(.began) {
                    let location = self.convert(event.locationInWindow, from: nil)
                    let isOnCanvas = event.window === self.window && self.bounds.contains(location)
                    self.onScrollBegan(isOnCanvas ? location : nil, event.modifierFlags.contains(.control))
                }
                // The decision from the start of the scroll stays until the momentum ends.
                let delta = CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY)
                return self.onScroll(delta) ? nil : event
            }
            // The same keys as in Finder. During a rename, the keys go to the name field.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, !(self.window?.firstResponder is NSText),
                      let command = Self.command(for: event)
                else { return event }
                if event.window is QLPreviewPanel {
                    // While the Quick Look panel has the keys, the arrow keys continue to move the
                    // selection, as in Finder. The panel does the other keys: Space and Escape close it.
                    guard case .moveSelection = command else { return event }
                } else if event.window !== self.window {
                    return event
                }
                return self.onCommand(command) ? nil : event
            }
        }

        private static let returnKey: UInt16 = 36
        private static let keypadEnterKey: UInt16 = 76
        private static let deleteKey: UInt16 = 51
        private static let escapeKey: UInt16 = 53
        private static let spaceKey: UInt16 = 49
        private static let leftArrowKey: UInt16 = 123
        private static let rightArrowKey: UInt16 = 124
        private static let downArrowKey: UInt16 = 125
        private static let upArrowKey: UInt16 = 126

        private static func command(for event: NSEvent) -> CanvasCommand? {
            let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
            // The character that the key gives with Command. On a keyboard layout without
            // Latin letters, this is the Latin letter, as for menu commands.
            let character = event.characters(byApplyingModifiers: .command)?.lowercased()
            switch (modifiers, event.keyCode, character) {
            case ([], returnKey, _), ([], keypadEnterKey, _): return .rename
            case (.command, deleteKey, _): return .moveToTrash
            case ([], escapeKey, _): return .closeCard
            case ([], spaceKey, _): return .quickLook
            case ([], upArrowKey, _): return .moveSelection(.up)
            case ([], downArrowKey, _): return .moveSelection(.down)
            case ([], leftArrowKey, _): return .moveSelection(.left)
            case ([], rightArrowKey, _): return .moveSelection(.right)
            case (.command, upArrowKey, _): return .showParentFolder
            case (.command, downArrowKey, _): return .openSelection
            case (.command, _, "1"): return .viewMode(.icons)
            case (.command, _, "2"): return .viewMode(.list)
            case (.command, _, "c"): return .copy
            case (.command, _, "v"): return .paste
            case ([.command, .option], _, "v"): return .pasteAndMove
            case (.command, _, "z"): return .undo
            case ([.command, .shift], _, "n"): return .newFolder
            default: return nil
            }
        }

        override func removeFromSuperview() {
            removeMonitor()
            super.removeFromSuperview()
        }

        private func removeMonitor() {
            if let magnifyMonitor { NSEvent.removeMonitor(magnifyMonitor) }
            magnifyMonitor = nil
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            scrollMonitor = nil
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }

        override func mouseDown(with event: NSEvent) {
            onMouseDown()
        }

        override func mouseDragged(with event: NSEvent) {
            onPan(CGSize(width: event.deltaX, height: event.deltaY))
        }
    }
}
