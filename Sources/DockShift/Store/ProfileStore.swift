import Combine
import Foundation

/// Owns the saved profiles and the record of which one is active.
/// Persists to `~/Library/Application Support/DockShift/profiles.json`.
@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [DockProfile] = []
    /// The macOS Dock profile currently applied to Apple's Dock.
    @Published private(set) var activeProfileID: UUID?
    /// The Custom Dock profile currently shown in DockShift's own Dock.
    @Published private(set) var activeCustomProfileID: UUID?
    @Published var lastError: String?

    /// When we last rewrote the Dock ourselves; used to ignore our own plist changes.
    private(set) var lastAppliedAt: Date = .distantPast

    private let fileURL: URL

    private struct Persisted: Codable {
        var version = 1
        var profiles: [DockProfile]
        var activeProfileID: UUID?
        var activeCustomProfileID: UUID?
    }

    struct Backup: Codable {
        var app = "DockShift"
        var version = 1
        var exportedAt: Date
        var profiles: [DockProfile]
    }

    init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DockShift", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("profiles.json")
        load()
    }

    var activeProfile: DockProfile? {
        profiles.first { $0.id == activeProfileID }
    }

    var activeCustomProfile: DockProfile? {
        profiles.first { $0.id == activeCustomProfileID }
    }

    func profile(id: UUID) -> DockProfile? {
        profiles.first { $0.id == id }
    }

    func profiles(of kind: ProfileKind) -> [DockProfile] {
        profiles.filter { $0.kind == kind }
    }

    func isActive(_ profile: DockProfile) -> Bool {
        switch profile.kind {
        case .macOSDock: return profile.id == activeProfileID
        case .customDock: return profile.id == activeCustomProfileID
        }
    }

    // MARK: - Creating and editing

    /// Snapshots the Dock as it is right now. The Dock already matches, so the
    /// new profile becomes the active one without a restart.
    @discardableResult
    func createFromCurrentDock(name: String) -> DockProfile {
        let profile = DockProfile(name: uniqueName(name), items: DockBridge.currentItems())
        profiles.append(profile)
        activeProfileID = profile.id
        save()
        return profile
    }

    @discardableResult
    func createEmpty(name: String, kind: ProfileKind = .macOSDock) -> DockProfile {
        let profile = DockProfile(name: uniqueName(name), kind: kind)
        profiles.append(profile)
        // The first Custom Dock profile is shown right away; nothing to restart.
        if kind == .customDock, activeCustomProfileID == nil {
            activeCustomProfileID = profile.id
        }
        save()
        return profile
    }

    func update(_ profile: DockProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = profile
        updated.updatedAt = Date()
        profiles[index] = updated
        save()
    }

    func delete(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileID == id { activeProfileID = nil }
        if activeCustomProfileID == id { activeCustomProfileID = nil }
        save()
    }

    @discardableResult
    func duplicate(_ id: UUID) -> DockProfile? {
        guard let source = profile(id: id) else { return nil }
        var copy = source
        copy.id = UUID()
        copy.name = uniqueName(source.name + " copy")
        copy.shortcut = nil
        copy.createdAt = Date()
        copy.updatedAt = Date()
        profiles.append(copy)
        save()
        return copy
    }

    /// Edits a profile's items in place, e.g. from the Custom Dock's context menus.
    func updateItems(of id: UUID, _ transform: (inout [DockItem]) -> Void) {
        guard var target = profile(id: id) else { return }
        transform(&target.items)
        update(target)
    }

    /// Overwrites a profile's items with whatever is pinned right now.
    func replaceWithCurrentDock(_ id: UUID) {
        guard var target = profile(id: id) else { return }
        target.items = DockBridge.currentItems()
        update(target)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        profiles.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Applying

    /// Mirrors the Settings toggle; the overlay also needs Screen Recording permission.
    var smoothSwitching = true

    /// Makes the profile active. macOS Dock profiles are written to Apple's
    /// Dock, which is then restarted; Custom Dock profiles just swap in place.
    func apply(_ id: UUID) {
        guard let target = profile(id: id) else { return }
        if target.kind == .customDock {
            activeCustomProfileID = id
            lastError = nil
            save()
            return
        }
        lastAppliedAt = Date()
        do {
            if smoothSwitching {
                try DockTransition.perform { try DockBridge.apply(target.items) }
            } else {
                try DockBridge.apply(target.items)
            }
            activeProfileID = id
            lastError = nil
            save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Call before restarting the Dock for reasons other than applying a
    /// profile, so the auto-save watcher ignores the resulting plist churn.
    func noteDockRestart() {
        lastAppliedAt = Date()
    }

    /// Pulls changes made directly in Apple's Dock into the active profile.
    func syncActiveFromDock() {
        guard Date().timeIntervalSince(lastAppliedAt) > 5, var active = activeProfile else { return }
        let current = DockBridge.currentItems()
        // An empty read usually means the Dock is mid-restart; never wipe a profile for it.
        guard !current.isEmpty, current != active.items else { return }
        active.items = current
        update(active)
    }

    // MARK: - Backup

    func exportBackup(to url: URL) throws {
        var exported = profiles
        for index in exported.indices { exported[index].shortcut = nil }
        let backup = Backup(exportedAt: Date(), profiles: exported)
        let data = try ProfileStore.encoder.encode(backup)
        try data.write(to: url, options: .atomic)
    }

    /// Adds the backed-up profiles as copies. Existing profiles are untouched.
    @discardableResult
    func importBackup(from url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        let backup = try ProfileStore.decoder.decode(Backup.self, from: data)
        for var restored in backup.profiles {
            restored.id = UUID()
            restored.name = uniqueName(restored.name)
            restored.shortcut = nil
            profiles.append(restored)
        }
        save()
        return backup.profiles.count
    }

    // MARK: - Persistence

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let persisted = try? ProfileStore.decoder.decode(Persisted.self, from: data)
        else { return }
        profiles = persisted.profiles
        activeProfileID = persisted.activeProfileID
        activeCustomProfileID = persisted.activeCustomProfileID
    }

    private func save() {
        let persisted = Persisted(
            profiles: profiles,
            activeProfileID: activeProfileID,
            activeCustomProfileID: activeCustomProfileID
        )
        do {
            let data = try ProfileStore.encoder.encode(persisted)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            lastError = "Could not save profiles: \(error.localizedDescription)"
        }
    }

    private func uniqueName(_ proposed: String) -> String {
        let base = proposed.trimmingCharacters(in: .whitespaces)
        let name = base.isEmpty ? "Dock" : base
        let existing = Set(profiles.map(\.name))
        guard existing.contains(name) else { return name }
        var counter = 2
        while existing.contains("\(name) \(counter)") { counter += 1 }
        return "\(name) \(counter)"
    }
}
