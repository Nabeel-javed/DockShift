import AppKit
import SwiftUI

/// Creates and reuses the app's windows. Each is an NSWindow hosting SwiftUI,
/// which keeps window control straightforward for a menu bar app.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var editorWindow: NSWindow?
    private var settingsWindow: NSWindow?

    private init() {}

    func showEditor(store: ProfileStore, settings: AppSettings) {
        if editorWindow == nil {
            let root = EditorView()
                .environmentObject(store)
                .environmentObject(settings)
            let window = makeWindow(title: "Manage Docks", size: NSSize(width: 860, height: 560), root: root)
            window.minSize = NSSize(width: 760, height: 480)
            window.setFrameAutosaveName("ManageDocks")
            editorWindow = window
        }
        present(editorWindow!)
    }

    func showSettings(store: ProfileStore, settings: AppSettings) {
        if settingsWindow == nil {
            let root = SettingsView()
                .environmentObject(store)
                .environmentObject(settings)
            let window = makeWindow(title: "Settings", size: NSSize(width: 520, height: 420), root: root)
            window.styleMask.remove(.resizable)
            settingsWindow = window
        }
        present(settingsWindow!)
    }

    private func makeWindow<Root: View>(title: String, size: NSSize, root: Root) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentViewController = NSHostingController(rootView: root)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
