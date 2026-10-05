import AppKit

@main
enum DockShiftApp {
    @MainActor
    static func main() {
        // Developer aid: print what the Dock has pinned and exit, without launching the UI.
        if CommandLine.arguments.contains("--dump") {
            for (index, item) in DockBridge.currentItems().enumerated() {
                switch item {
                case .app(let app):
                    print("\(index + 1). \(app.label)  \(app.path)  [\(app.bundleIdentifier ?? "-")]")
                case .spacer(let size):
                    print("\(index + 1). <\(size.rawValue) spacer>")
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
