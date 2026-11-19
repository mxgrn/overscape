import AppKit
import SwiftUI

/// An AppKit view behind the cards that turns raw input into canvas navigation:
/// - pinch anywhere in the canvas zooms around the cursor,
/// - two-finger scroll or the mouse wheel on empty canvas pans,
/// - a mouse drag on empty canvas pans.
struct CanvasEventView: NSViewRepresentable {
    var onPan: (CGSize) -> Void
    var onMagnify: (_ factor: CGFloat, _ location: CGPoint) -> Void

    func makeNSView(context: Context) -> EventNSView {
        let view = EventNSView()
        view.onPan = onPan
        view.onMagnify = onMagnify
        return view
    }

    func updateNSView(_ view: EventNSView, context: Context) {
        view.onPan = onPan
        view.onMagnify = onMagnify
    }

    final class EventNSView: NSView {
        var onPan: (CGSize) -> Void = { _ in }
        var onMagnify: (CGFloat, CGPoint) -> Void = { _, _ in }
        private var magnifyMonitor: Any?

        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            // A pinch over a card goes to the card's scroll view, not to this view.
            // A local monitor sees every pinch in the window, so the zoom works everywhere.
            magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let location = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(location) else { return event }
                self.onMagnify(1 + event.magnification, location)
                return nil
            }
        }

        override func removeFromSuperview() {
            removeMonitor()
            super.removeFromSuperview()
        }

        private func removeMonitor() {
            if let magnifyMonitor { NSEvent.removeMonitor(magnifyMonitor) }
            magnifyMonitor = nil
        }

        override func scrollWheel(with event: NSEvent) {
            // A classic mouse wheel reports lines, not points.
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
            onPan(CGSize(width: event.scrollingDeltaX * scale, height: event.scrollingDeltaY * scale))
        }

        override func mouseDragged(with event: NSEvent) {
            onPan(CGSize(width: event.deltaX, height: event.deltaY))
        }
    }
}
