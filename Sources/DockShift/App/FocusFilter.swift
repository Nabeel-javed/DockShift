import AppIntents
import AppKit
import Foundation

/// The "Switch Dock" Focus Filter. Users attach it to a Focus in
/// System Settings → Focus → Focus Filters; macOS then runs `perform()` when
/// the Focus turns on. Turning the Focus off keeps the last Dock, matching
/// how the app behaves elsewhere.
///
/// macOS only discovers this intent when the app bundle carries App Intents
/// metadata, which Xcode's build pipeline generates.
struct SwitchDockFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Switch Dock"
    static var description: IntentDescription? = IntentDescription("Switch to a saved Dock when this Focus turns on.")

    @Parameter(title: "Dock")
    var profile: DockProfileEntity?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "Switch Dock",
            subtitle: profile.map { LocalizedStringResource(stringLiteral: $0.name) } ?? "No Dock chosen"
        )
    }

    func perform() async throws -> some IntentResult {
        if let profile {
            await FocusFilterBridge.apply(profile.id)
        }
        return .result()
    }
}

/// A saved Dock as seen by Shortcuts and Focus.
struct DockProfileEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Dock"
    static var defaultQuery = DockProfileQuery()

    var id: UUID
    var name: String
    var kind: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name), subtitle: LocalizedStringResource(stringLiteral: kind))
    }
}

struct DockProfileQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [DockProfileEntity] {
        await FocusFilterBridge.allProfiles().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [DockProfileEntity] {
        await FocusFilterBridge.allProfiles()
    }
}

/// Hands intent requests to the running app's store.
@MainActor
enum FocusFilterBridge {
    private static var store: ProfileStore? {
        (NSApp.delegate as? AppDelegate)?.store
    }

    static func allProfiles() -> [DockProfileEntity] {
        (store?.profiles ?? []).map { DockProfileEntity(id: $0.id, name: $0.name, kind: $0.kind.title) }
    }

    static func apply(_ id: UUID) {
        store?.apply(id)
    }
}
