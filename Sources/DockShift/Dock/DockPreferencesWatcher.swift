import Foundation

/// Watches `com.apple.dock.plist` so edits made directly in Apple's Dock can be
/// synced back into the active profile. cfprefsd replaces the file atomically,
/// so the descriptor is reopened after every rename.
final class DockPreferencesWatcher {
    var onChange: (@MainActor () -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private let url = DockBridge.preferencesFileURL

    func start() {
        open()
    }

    func stop() {
        source?.cancel()
        source = nil
        pending?.cancel()
    }

    private func open() {
        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.open() }
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self, let current = self.source else { return }
            let flags = current.data
            self.scheduleChange()
            if flags.contains(.rename) || flags.contains(.delete) {
                self.reopen()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
    }

    private func reopen() {
        source?.cancel()
        source = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.open() }
    }

    /// The Dock writes several keys in quick succession; wait for it to settle.
    private func scheduleChange() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let handler = self?.onChange else { return }
            Task { @MainActor in handler() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}
