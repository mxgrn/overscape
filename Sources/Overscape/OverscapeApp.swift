import AppKit
import SwiftUI

@main
struct OverscapeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // One window, so that there is one canvas to save and restore.
        Window("Overscape", id: "canvas") {
            CanvasView(model: appDelegate.model)
                .frame(minWidth: 800, minHeight: 500)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: CanvasModel = {
        let model = CanvasModel()
        if let snapshot = SnapshotStore.load() {
            model.restore(snapshot)
        }
        return model
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A bare SwiftPM executable starts as a background process.
        // Make it a regular app with a Dock icon and bring it to the front.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        do {
            try SnapshotStore.save(model.snapshot)
        } catch {
            NSLog("Overscape: cannot save the canvas: \(error)")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
