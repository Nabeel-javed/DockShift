import AppKit
import Foundation

/// Keeps Apple's Dock out of sight while the Custom Dock is the main Dock.
///
/// macOS has no way to remove the Dock: the same process also runs Mission
/// Control, the app switcher, Launchpad and Spaces, and launchd restarts it
/// at once if it is killed. So while suppressing, DockShift turns on
/// auto-hide with a reveal delay of over a day, stops icons bouncing up
/// through the hidden Dock, and hides it again within a second if ⌘⌥D or
/// System Settings turns hiding off. The user's own settings are saved
/// before the first change and put back by `restore()`, on the next launch
/// too if DockShift never got to quit cleanly.
@MainActor
final class AppleDockSuppressor {
    /// Called just before DockShift restarts Apple's Dock.
    var willRestartDock: () -> Void = {}
    /// Called after ⌘⌥D or System Settings turned Dock hiding off and Apple's
    /// Dock was hidden again.
    var hidingToggledExternally: () -> Void = {}

    private static let savedStateKey = "appleDockStateBeforeCustomDock"
    private static let suppressedValues: [String: NSObject?] = [
        "autohide": NSNumber(value: true),
        // Seconds the pointer would have to rest at the edge: over a day.
        "autohide-delay": NSNumber(value: 100_000.0),
        // Apps asking for attention otherwise bounce their icon up out of the hidden Dock.
        "no-bouncing": NSNumber(value: true),
    ]

    private var watchdog: Timer?

    /// The user's own values for the keys DockShift changes; absent keys were unset.
    private var savedState: [String: Any]? {
        UserDefaults.standard.dictionary(forKey: Self.savedStateKey)
    }

    func suppress() {
        if savedState == nil {
            var state: [String: Any] = [:]
            for key in Self.suppressedValues.keys {
                if let value = DockBridge.preference(key) { state[key] = value }
            }
            UserDefaults.standard.set(state, forKey: Self.savedStateKey)
        }
        willRestartDock()
        DockTransition.perform { DockBridge.setPreferences(Self.suppressedValues) }
        startWatchdog()
    }

    func restore() {
        watchdog?.invalidate()
        watchdog = nil
        guard let state = savedState else { return }
        UserDefaults.standard.removeObject(forKey: Self.savedStateKey)
        var values: [String: NSObject?] = [:]
        for key in Self.suppressedValues.keys {
            // updateValue keeps nil entries, which remove keys that were unset.
            values.updateValue(state[key] as? NSObject, forKey: key)
        }
        willRestartDock()
        DockTransition.perform { DockBridge.setPreferences(values) }
    }

    private func startWatchdog() {
        guard watchdog == nil else { return }
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.keepHidden() }
        }
    }

    /// ⌘⌥D and System Settings switch Dock hiding live; switch it straight back.
    private func keepHidden() {
        guard savedState != nil, !DockBridge.isAutoHidden else { return }
        DockBridge.setAutoHiddenNow(true)
        hidingToggledExternally()
    }
}
