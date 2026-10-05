import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ProfileStore()
    let settings = AppSettings()

    private var statusItem: StatusItemController?
    private let watcher = DockPreferencesWatcher()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(store: store, settings: settings)

        HotKeyManager.shared.onTrigger = { [weak self] id in
            self?.store.apply(id)
        }
        store.$profiles
            .sink { HotKeyManager.shared.sync(profiles: $0) }
            .store(in: &cancellables)
        settings.$smoothSwitching
            .sink { [weak self] in self?.store.smoothSwitching = $0 }
            .store(in: &cancellables)

        watcher.onChange = { [weak self] in
            guard let self, self.settings.autoSaveDockChanges else { return }
            self.store.syncActiveFromDock()
        }
        watcher.start()

        if store.profiles.isEmpty {
            WindowManager.shared.showEditor(store: store, settings: settings)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
