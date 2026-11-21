import AppKit
import SwiftUI

@main
struct OverscapeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // One window, so that there is one set of workspaces to save and restore.
        Window("Overscape", id: "canvas") {
            MainView(workspaces: appDelegate.workspaces)
                .frame(minWidth: 900, minHeight: 500)
        }
    }
}

enum AppIcon {
    /// The app icon. `Assets/AppIcon.svg` is the source of the PNG file.
    static var image: NSImage? {
        Bundle.module.url(forResource: "AppIcon", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let workspaces: WorkspacesModel = {
        let model = WorkspacesModel()
        if let snapshot = WorkspacesFile.load() {
            model.restore(snapshot)
        } else if let legacy = SnapshotStore.load() {
            // A file from a version without workspaces.
            model.restore(legacyCanvas: legacy)
        }
        return model
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A bare SwiftPM executable starts as a background process.
        // Make it a regular app with a Dock icon and bring it to the front.
        NSApp.setActivationPolicy(.regular)
        // There is no app bundle, so the Dock icon comes from the package resources.
        NSApp.applicationIconImage = AppIcon.image
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        do {
            try WorkspacesFile.save(workspaces.snapshot)
        } catch {
            NSLog("Overscape: cannot save the canvas: \(error)")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
