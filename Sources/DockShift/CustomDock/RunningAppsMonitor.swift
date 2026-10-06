import AppKit
import Combine

/// Tracks which regular apps are running and which is frontmost.
@MainActor
final class RunningAppsMonitor: ObservableObject {
    @Published private(set) var running: [NSRunningApplication] = []
    @Published private(set) var frontmostBundleID: String?
    /// Paths of apps opened from the Dock that haven't finished launching yet.
    @Published private(set) var launching: Set<String> = []

    private var cancellables = Set<AnyCancellable>()

    init() {
        refresh()
        NSWorkspace.shared.publisher(for: \.runningApplications)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if let path = app?.bundleURL?.path { self?.launching.remove(path) }
            }
            .store(in: &cancellables)
    }

    /// Bounces the app's tile until it finishes launching (or 20 seconds pass).
    func markLaunching(_ path: String) {
        launching.insert(path)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            self?.launching.remove(path)
        }
    }

    private func refresh() {
        running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func app(matching reference: AppReference) -> NSRunningApplication? {
        running.first { candidate in
            if let id = reference.bundleIdentifier, id == candidate.bundleIdentifier { return true }
            return candidate.bundleURL?.path == reference.path
        }
    }

    func isRunning(_ reference: AppReference) -> Bool {
        app(matching: reference) != nil
    }

    /// Running apps that are not pinned in `items`, for the "Show running apps" section.
    func unpinned(given items: [DockItem]) -> [NSRunningApplication] {
        let pinnedIDs = Set(items.compactMap { item -> String? in
            if case .app(let app) = item { return app.bundleIdentifier ?? app.path }
            return nil
        })
        return running.filter { app in
            guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
            if let id = app.bundleIdentifier, pinnedIDs.contains(id) { return false }
            if let path = app.bundleURL?.path, pinnedIDs.contains(path) { return false }
            return true
        }
    }
}
