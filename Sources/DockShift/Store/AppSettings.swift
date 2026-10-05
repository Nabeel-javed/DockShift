import Combine
import Foundation
import ServiceManagement

/// App-wide preferences, backed by UserDefaults (and SMAppService for login).
@MainActor
final class AppSettings: ObservableObject {
    @Published var showProfileNameInMenuBar: Bool {
        didSet { defaults.set(showProfileNameInMenuBar, forKey: Keys.showProfileName) }
    }

    @Published var autoSaveDockChanges: Bool {
        didSet { defaults.set(autoSaveDockChanges, forKey: Keys.autoSave) }
    }

    @Published var launchAtLogin: Bool {
        didSet { if !isReverting { updateLoginItem(oldValue: oldValue) } }
    }

    @Published var smoothSwitching: Bool {
        didSet { defaults.set(smoothSwitching, forKey: Keys.smoothSwitching) }
    }

    @Published var loginItemError: String?

    private let defaults = UserDefaults.standard
    private var isReverting = false

    private enum Keys {
        static let showProfileName = "showProfileNameInMenuBar"
        static let autoSave = "autoSaveDockChanges"
        static let smoothSwitching = "smoothSwitching"
    }

    init() {
        showProfileNameInMenuBar = defaults.object(forKey: Keys.showProfileName) as? Bool ?? true
        autoSaveDockChanges = defaults.bool(forKey: Keys.autoSave)
        smoothSwitching = defaults.object(forKey: Keys.smoothSwitching) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func updateLoginItem(oldValue: Bool) {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
            isReverting = true
            launchAtLogin = oldValue
            isReverting = false
        }
    }
}
