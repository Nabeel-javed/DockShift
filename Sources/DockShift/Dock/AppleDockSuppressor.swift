import AppKit
import Foundation

/// Keeps Apple's Dock out of sight while the Custom Dock replaces it.
///
/// macOS has no way to remove the Dock: the same process also runs Mission
/// Control, the app switcher, Launchpad and Spaces, and launchd restarts it
/// at once if it is killed. Auto-hide alone isn't enough either, because the
/// hidden Dock still slides in over the Custom Dock when the pointer reaches
/// their shared edge. So while suppressing, DockShift moves Apple's Dock to a
/// side edge the Custom Dock doesn't use, shrinks it, auto-hides it with long
/// reveal and animation times, and stops icons popping out of it. If ⌘⌥D or
/// System Settings shows it again, it is hidden again within a second.
///
/// The user's own values are saved before the first change and put back by
/// `restore`; a helper process puts them back if DockShift crashes or is
/// force-quit. Every change runs in order on `DockBridge.queue`.
@MainActor
final class AppleDockSuppressor {
    /// Called just before DockShift changes Apple's Dock.
    var willRestartDock: () -> Void = {}
    /// Called after ⌘⌥D or System Settings showed Apple's Dock while it was
    /// suppressed (it is hidden again right away).
    var hidingToggledExternally: () -> Void = {}

    private nonisolated static let savedStateKey = "appleDockSavedState"

    /// The Dock settings that keep Apple's Dock away from a Custom Dock on `edge`.
    private nonisolated static func suppressedValues(avoiding edge: DockPosition) -> [String: NSObject?] {
        [
            "autohide": NSNumber(value: true),
            // Seconds the pointer must rest at the edge before the Dock slides in.
            "autohide-delay": NSNumber(value: 1000.0),
            // Slows the slide-in animation, in case a reveal starts anyway.
            "autohide-time-modifier": NSNumber(value: 1000.0),
            // Off the Custom Dock's edge, so that edge only ever shows the Custom Dock.
            "orientation": (edge == .left ? "right" : "left") as NSString,
            "tilesize": NSNumber(value: 16),
            // Launching apps and apps asking for attention otherwise pop an icon out of the hidden Dock.
            "launchanim": NSNumber(value: false),
            "no-bouncing": NSNumber(value: true),
        ]
    }

    private nonisolated static var managedKeys: [String] {
        Array(suppressedValues(avoiding: .bottom).keys).sorted()
    }

    private var watchdog: Timer?
    /// Changes queued on `DockBridge.queue` and not yet finished.
    private var pendingChanges = 0

    /// Hides Apple's Dock on the side away from a Custom Dock on `edge`.
    func suppress(avoiding edge: DockPosition) {
        enqueue { Self.performSuppress(avoiding: edge) }
        startWatchdog()
    }

    /// Puts the user's Dock settings back. With `wait`, returns only once done
    /// (used while quitting).
    func restore(wait: Bool = false) {
        watchdog?.invalidate()
        watchdog = nil
        if wait {
            willRestartDock()
            DockBridge.queue.sync { Self.restoreSavedState() }
        } else {
            enqueue { Self.restoreSavedState() }
        }
    }

    private func enqueue(_ change: @escaping @Sendable () -> Void) {
        willRestartDock()
        pendingChanges += 1
        DockBridge.queue.async { [weak self] in
            change()
            Task { @MainActor in
                self?.pendingChanges -= 1
                self?.willRestartDock()
            }
        }
    }

    // MARK: - Saved state

    /// Saves the user's own value of every managed key before the first change,
    /// then applies the suppressed values. Runs on `DockBridge.queue`, so the
    /// values it saves are never ones a pending change is about to replace.
    private nonisolated static func performSuppress(avoiding edge: DockPosition) {
        var state = savedState() ?? (keys: [], values: [:])
        for key in managedKeys where !state.keys.contains(key) {
            state.keys.append(key)
            if let value = DockBridge.preference(key) { state.values[key] = value }
        }
        saveState(state)
        DockBridge.applyOutOfSight(suppressedValues(avoiding: edge))
    }

    /// The keys DockShift changed and their original values; a key listed
    /// without a value was unset.
    private nonisolated static func savedState() -> (keys: [String], values: [String: Any])? {
        guard let dictionary = UserDefaults.standard.dictionary(forKey: savedStateKey),
              let keys = dictionary["keys"] as? [String] else { return nil }
        return (keys, dictionary["values"] as? [String: Any] ?? [:])
    }

    private nonisolated static func saveState(_ state: (keys: [String], values: [String: Any])) {
        UserDefaults.standard.set(["keys": state.keys, "values": state.values], forKey: savedStateKey)
        // Flush now: the crash helper reads this from another process.
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    }

    /// Puts back the user's saved Dock settings, if any. Also used by the crash
    /// helper (`animated: false`), where no app is running.
    nonisolated static func restoreSavedState(animated: Bool = true) {
        guard let state = savedState() else { return }
        var values: [String: NSObject?] = [:]
        for key in state.keys {
            // updateValue keeps nil entries, which remove keys that were unset.
            values.updateValue(state.values[key] as? NSObject, forKey: key)
        }
        DockBridge.applyOutOfSight(values, animated: animated)
        UserDefaults.standard.removeObject(forKey: savedStateKey)
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    }

    /// Starts a helper that waits for this process to end and, if DockShift
    /// never got to restore Apple's Dock (a crash or Force Quit), restores it
    /// by running `DockShift --restore-dock`.
    nonisolated static func startCrashHelper() {
        guard let executable = Bundle.main.executablePath else { return }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            "-c", #"while kill -0 "$1" 2>/dev/null; do sleep 1; done; exec "$2" --restore-dock"#,
            "dockshift-crash-helper", String(getpid()), executable,
        ]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try? helper.run()
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        guard watchdog == nil else { return }
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.keepHidden() }
        }
    }

    /// ⌘⌥D and System Settings show the Dock live; hide it straight away again.
    private func keepHidden() {
        guard pendingChanges == 0, Self.savedState() != nil else { return }
        let hidden = DockBridge.isHiddenLive ?? DockBridge.isAutoHidden
        guard !hidden else { return }
        enqueue { DockBridge.rehide() }
        hidingToggledExternally()
    }
}
