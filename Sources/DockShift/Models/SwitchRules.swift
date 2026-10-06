import Foundation

/// When to switch Docks automatically.
enum SwitchTrigger: Codable, Hashable {
    /// An app comes to the front.
    case app(bundleID: String, name: String)
    /// A time of day on some weekdays (1 = Sunday … 7 = Saturday, like Calendar).
    case schedule(hour: Int, minute: Int, weekdays: Set<Int>)
}

/// "When this happens, use that Dock."
struct SwitchRule: Codable, Hashable, Identifiable {
    var id = UUID()
    var trigger: SwitchTrigger
    var profileID: UUID?
    var isEnabled = true
}

/// Rules plus how app rules end.
struct AutomationSettings: Codable, Equatable {
    var rules: [SwitchRule] = []
    /// Go back to the previous Dock once the rule's app is no longer in front.
    var switchBackWhenAppLeaves = true
}
