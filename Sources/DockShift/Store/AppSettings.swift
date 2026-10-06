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

    @Published var dockSetup: DockSetup {
        didSet { defaults.set(dockSetup.rawValue, forKey: Keys.dockSetup) }
    }

    @Published var automation: AutomationSettings {
        didSet {
            if let data = try? JSONEncoder().encode(automation) {
                defaults.set(data, forKey: Keys.automation)
            }
        }
    }

    @Published var customDock: CustomDockSettings {
        didSet {
            if let data = try? JSONEncoder().encode(customDock) {
                defaults.set(data, forKey: Keys.customDock)
            }
        }
    }

    @Published var loginItemError: String?

    private let defaults = UserDefaults.standard
    private var isReverting = false

    private enum Keys {
        static let showProfileName = "showProfileNameInMenuBar"
        static let autoSave = "autoSaveDockChanges"
        static let smoothSwitching = "smoothSwitching"
        static let dockSetup = "dockSetup"
        static let customDock = "customDockSettings"
        static let automation = "automationSettings"
    }

    init() {
        // Off by default: a wider item is the first one macOS hides beside the notch.
        showProfileNameInMenuBar = defaults.object(forKey: Keys.showProfileName) as? Bool ?? false
        autoSaveDockChanges = defaults.bool(forKey: Keys.autoSave)
        smoothSwitching = defaults.object(forKey: Keys.smoothSwitching) as? Bool ?? true
        dockSetup = DockSetup(rawValue: defaults.string(forKey: Keys.dockSetup) ?? "") ?? .macOSOnly
        if let data = defaults.data(forKey: Keys.automation),
           let decoded = try? JSONDecoder().decode(AutomationSettings.self, from: data) {
            automation = decoded
        } else {
            automation = AutomationSettings()
        }
        if let data = defaults.data(forKey: Keys.customDock),
           let decoded = try? JSONDecoder().decode(CustomDockSettings.self, from: data) {
            customDock = decoded
        } else {
            customDock = CustomDockSettings()
        }
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
