import AppKit

@main
enum DockShiftApp {
    @MainActor
    static func main() {
        // Crash recovery, run by the helper once DockShift has exited: put Apple's
        // Dock back unless a new DockShift instance has taken over since.
        if CommandLine.arguments.contains("--restore-dock") {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                .filter { $0.processIdentifier != getpid() && !$0.isTerminated }
            if others.isEmpty {
                AppleDockSuppressor.restoreSavedState()
            }
            return
        }

        // Developer aid: print what the Dock has pinned and exit, without launching the UI.
        if CommandLine.arguments.contains("--dump") {
            for (index, item) in DockBridge.currentItems().enumerated() {
                switch item {
                case .app(let app):
                    print("\(index + 1). \(app.label)  \(app.path)  [\(app.bundleIdentifier ?? "-")]")
                case .spacer(let size):
                    print("\(index + 1). <\(size.rawValue) spacer>")
                default:
                    print("\(index + 1). <unsupported in macOS Dock>")
                }
            }
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
