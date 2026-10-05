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
    private let savedDelayKey = "appleDockAutoHideDelayBeforeCustomMain"
    /// Reveal delay given to Apple's hidden Dock while the Custom Dock is the
    /// main Dock: long enough that the screen edge belongs to the Custom Dock.
    private let replacementRevealDelay = 100_000.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(store: store, settings: settings)
        customDock = CustomDockController(store: store, settings: settings)

        settings.$dockSetup
            .removeDuplicates()
            .sink { [weak self] setup in
                guard let self else { return }
                // A Custom Dock with nothing in it is no replacement; start from the real Dock.
                if setup.showsCustomDock, self.store.profiles(of: .customDock).isEmpty {
                    self.store.createFromCurrentDock(name: "Custom Dock", kind: .customDock)
                }
                self.applyAppleDockVisibility(for: setup)
            }
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
                let wasHidden = DockBridge.isAutoHidden
                defaults.set(wasHidden, forKey: savedAutoHideKey)
                defaults.set(DockBridge.autoHideDelay, forKey: savedDelayKey)
                // Behave like the Dock being replaced: hidden if it was hidden.
                settings.customDock.autoHide = wasHidden
            }
            store.noteDockRestart()
            DockTransition.perform { DockBridge.configureAutoHide(hidden: true, delay: replacementRevealDelay) }
        } else {
            restoreAppleDockVisibility()
        }
    }

    private func restoreAppleDockVisibility() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: savedAutoHideKey) != nil else { return }
        let previous = defaults.bool(forKey: savedAutoHideKey)
        let previousDelay = defaults.object(forKey: savedDelayKey) as? Double
        defaults.removeObject(forKey: savedAutoHideKey)
        defaults.removeObject(forKey: savedDelayKey)
        store.noteDockRestart()
        DockTransition.perform { DockBridge.configureAutoHide(hidden: previous, delay: previousDelay) }
    }
}
