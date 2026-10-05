import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ProfileStore()
    let settings = AppSettings()

    private var statusItem: StatusItemController?
    private var customDock: CustomDockController?
    private let watcher = DockPreferencesWatcher()
    private var cancellables = Set<AnyCancellable>()

    /// Apple's Dock auto-hide state before "Custom Dock as main Dock" changed it.
    private let savedAutoHideKey = "appleDockAutoHideBeforeCustomMain"

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(store: store, settings: settings)
        customDock = CustomDockController(store: store, settings: settings)

        settings.$dockSetup
            .removeDuplicates()
            .sink { [weak self] setup in self?.applyAppleDockVisibility(for: setup) }
            .store(in: &cancellables)

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

    func applicationWillTerminate(_ notification: Notification) {
        restoreAppleDockVisibility()
    }

    /// "Custom Dock as main Dock" auto-hides Apple's Dock while DockShift runs.
    private func applyAppleDockVisibility(for setup: DockSetup) {
        let defaults = UserDefaults.standard
        if setup == .customMain {
            if defaults.object(forKey: savedAutoHideKey) == nil {
                defaults.set(DockBridge.isAutoHidden, forKey: savedAutoHideKey)
            }
            store.noteDockRestart()
            DockTransition.perform { DockBridge.setAutoHidden(true) }
        } else {
            restoreAppleDockVisibility()
        }
    }

    private func restoreAppleDockVisibility() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: savedAutoHideKey) != nil else { return }
        let previous = defaults.bool(forKey: savedAutoHideKey)
        defaults.removeObject(forKey: savedAutoHideKey)
        store.noteDockRestart()
        DockTransition.perform { DockBridge.setAutoHidden(previous) }
    }
}
