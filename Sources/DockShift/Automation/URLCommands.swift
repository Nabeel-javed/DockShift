import AppKit

/// `dockshift://` links, so launchers, Stream Deck or Shortcuts can drive DockShift:
///
///     dockshift://switch/Work          use the Dock named "Work" (or ?name=Work)
///     dockshift://use/custom           use the Custom Dock
///     dockshift://use/original         use Apple's Dock
///     dockshift://next  /previous      cycle Docks of the kind in use
///     dockshift://manage  /settings    open those windows
@MainActor
enum URLCommands {
    static func handle(_ url: URL, store: ProfileStore, settings: AppSettings) {
        guard url.scheme?.lowercased() == "dockshift" else { return }
        let command = url.host?.lowercased() ?? ""
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let argument = query.first { $0.name == "name" || $0.name == "id" }?.value
            ?? url.pathComponents.dropFirst().joined(separator: "/")
        let kind: ProfileKind = settings.dockSetup.usesCustomDock ? .customDock : .macOSDock

        switch command {
        case "switch":
            if let profile = profile(named: argument, in: store) { store.apply(profile.id) }
        case "use":
            switch argument.lowercased() {
            case "custom": settings.dockSetup = DockSetup.setup(custom: true, keepingOriginal: settings.dockSetup == .both)
            case "original": settings.dockSetup = .macOSOnly
            default: break
            }
        case "next":
            store.cycleProfile(kind: kind, by: 1)
        case "previous":
            store.cycleProfile(kind: kind, by: -1)
        case "manage":
            WindowManager.shared.showEditor(store: store, settings: settings)
        case "settings":
            WindowManager.shared.showSettings(store: store, settings: settings)
        default:
            break
        }
    }

    /// A Dock by id, or by name ignoring case (Docks of the kind in use first).
    private static func profile(named name: String, in store: ProfileStore) -> DockProfile? {
        if let id = UUID(uuidString: name), let profile = store.profile(id: id) { return profile }
        return store.profiles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
