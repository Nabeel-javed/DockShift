import AppKit

/// Opens apps the way Apple's Dock does.
enum AppLauncher {
    /// Launches the app, or brings a running one forward. Going through Launch
    /// Services also sends a running app the "reopen" event, so an app whose
    /// last window was closed shows a new one instead of just becoming active.
    static func open(_ url: URL?, running: NSRunningApplication? = nil) {
        let pid = running?.processIdentifier
        guard let target = running?.bundleURL ?? url else {
            running?.activate(options: [.activateIgnoringOtherApps])
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: target, configuration: configuration) { _, error in
            guard error != nil, let pid else { return }
            DispatchQueue.main.async {
                NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps])
            }
        }
    }
}
