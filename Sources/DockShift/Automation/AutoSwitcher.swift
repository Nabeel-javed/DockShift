import AppKit
import Combine

/// Applies the user's switch rules: a Dock for an app while it's in front,
/// and Docks at set times.
@MainActor
final class AutoSwitcher {
    private let store: ProfileStore
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var pendingApp: DispatchWorkItem?
    private var scheduleTimer: Timer?
    /// The Dock to go back to (per Dock kind) once a rule's app leaves the front.
    private var previousProfile: [ProfileKind: UUID] = [:]
    /// Which app-rule profile is in effect, per Dock kind.
    private var appRuleProfile: [ProfileKind: UUID] = [:]
    /// Schedule rules already fired, keyed by rule and day.
    private var firedToday: Set<String> = []

    init(store: ProfileStore, settings: AppSettings) {
        self.store = store
        self.settings = settings

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.appActivated(app)
            }
            .store(in: &cancellables)

        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkSchedules() }
        }
    }

    // MARK: App rules

    private func appActivated(_ app: NSRunningApplication?) {
        // Wait a moment, so flicking through apps (⌘-Tab) doesn't thrash the Dock.
        pendingApp?.cancel()
        let bundleID = app?.bundleIdentifier
        guard bundleID != Bundle.main.bundleIdentifier else { return }
        let work = DispatchWorkItem { [weak self] in self?.applyAppRules(for: bundleID) }
        pendingApp = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func applyAppRules(for bundleID: String?) {
        let automation = settings.automation
        let matches = automation.rules.filter { rule in
            guard rule.isEnabled, case .app(let id, _) = rule.trigger else { return false }
            return id == bundleID
        }
        var handledKinds = Set<ProfileKind>()
        for rule in matches {
            guard let id = rule.profileID, let profile = store.profile(id: id) else { continue }
            handledKinds.insert(profile.kind)
            if appRuleProfile[profile.kind] == nil {
                previousProfile[profile.kind] = activeID(for: profile.kind)
            }
            appRuleProfile[profile.kind] = id
            if activeID(for: profile.kind) != id { store.apply(id) }
        }
        // An app without a rule is in front: undo earlier app rules if asked to.
        for kind in ProfileKind.allCases where !handledKinds.contains(kind) && appRuleProfile[kind] != nil {
            appRuleProfile[kind] = nil
            if automation.switchBackWhenAppLeaves, let previous = previousProfile[kind],
               store.profile(id: previous) != nil, activeID(for: kind) != previous {
                store.apply(previous)
            }
            previousProfile[kind] = nil
        }
    }

    private func activeID(for kind: ProfileKind) -> UUID? {
        kind == .customDock ? store.activeCustomProfileID : store.activeProfileID
    }

    // MARK: Schedules

    private func checkSchedules() {
        let now = Date()
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute, .weekday, .year, .month, .day], from: now)
        let today = "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
        for rule in settings.automation.rules where rule.isEnabled {
            guard case .schedule(let hour, let minute, let weekdays) = rule.trigger,
                  let id = rule.profileID, weekdays.contains(parts.weekday ?? 0) else { continue }
            let key = "\(rule.id)-\(today)"
            // Fire once in the first few minutes after the set time.
            let minutesPast = ((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) - (hour * 60 + minute)
            guard (0..<5).contains(minutesPast), !firedToday.contains(key) else { continue }
            firedToday.insert(key)
            store.apply(id)
        }
    }
}
