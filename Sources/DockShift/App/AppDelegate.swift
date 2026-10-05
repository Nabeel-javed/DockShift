import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ProfileStore()
    let settings = AppSettings()

    private var statusItem: StatusItemController?
    private var customDock: CustomDockController?
    private let watcher = DockPreferencesWatcher()
    private let appleDock = AppleDockSuppressor()
    private var signalSources: [DispatchSourceSignal] = []
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        quitCleanlyOnSignals()
        statusItem = StatusItemController(store: store, settings: settings)
        customDock = CustomDockController(store: store, settings: settings)

        appleDock.willRestartDock = { [weak self] in self?.store.noteDockRestart() }
        // With the Custom Dock in use, ⌘⌥D ("Turn Dock hiding on/off") applies to it.
        appleDock.hidingToggledExternally = { [weak self] in self?.settings.customDock.autoHide.toggle() }

        settings.$dockSetup
            .removeDuplicates()
            .sink { [weak self] setup in
                guard let self else { return }
                // A Custom Dock with nothing in it is no replacement; start from the real Dock.
                if setup.showsCustomDock, self.store.profiles(of: .customDock).isEmpty {
                    self.store.createFromCurrentDock(name: "Custom Dock", kind: .customDock)
                }
                // One Dock at a time: Apple's stays out of sight while the Custom Dock replaces it.
                if setup == .customMain {
                    self.appleDock.suppress()
                } else {
                    self.appleDock.restore()
                }
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
        appleDock.restore()
    }

    /// `kill`, `pkill` and Ctrl-C would otherwise end the app without putting
    /// Apple's Dock back; quit normally instead.
    private func quitCleanlyOnSignals() {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                Task { @MainActor in NSApp.terminate(nil) }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
