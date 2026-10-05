import AppKit
import Foundation

/// Reads and writes Apple's Dock settings and layout.
///
/// The Dock keeps its pinned items in the `persistent-apps` array of the
/// `com.apple.dock` preference domain, next to settings such as `autohide`.
/// Writing goes through `cfprefsd` via CFPreferences (the same route
/// `defaults write` takes); the Dock reads most of them only when it
/// relaunches, hence `killall Dock`.
enum DockBridge {
    private static let domain = "com.apple.dock" as CFString
    private static let appsKey = "persistent-apps" as CFString

    /// Serializes everything that restarts the Dock, so overlapping requests
    /// (fast switching, quitting mid-switch) apply in order.
    static let queue = DispatchQueue(label: "com.dockshift.dock-changes")

    static var preferencesFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.dock.plist")
    }

    /// The apps and spacers currently pinned to the Dock, in order.
    static func currentItems() -> [DockItem] {
        CFPreferencesAppSynchronize(domain)
        guard let raw = CFPreferencesCopyAppValue(appsKey, domain) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap(DockItem.init(dockEntry:))
    }

    /// The `persistent-apps` value for a layout.
    static func persistentApps(for items: [DockItem]) -> NSArray {
        items.compactMap { $0.dockEntry() } as NSArray
    }

    /// Whether Apple's Dock is set to auto-hide.
    static var isAutoHidden: Bool {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue("autohide" as CFString, domain) as? Bool ?? false
    }

    /// A raw value from the Dock's preferences, or nil when the key is unset.
    static func preference(_ key: String) -> NSObject? {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key as CFString, domain) as? NSObject
    }

    /// Writes Dock preferences (a nil value removes the key) and restarts the
    /// Dock once if anything changed.
    static func setPreferences(_ values: [String: NSObject?]) {
        guard hasChanges(values) else { return }
        write(values)
        restartDock()
    }

    static func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Changes without the pop

    /// Applies Dock preferences that need a restart without the Dock popping:
    /// a Dock on screen slides out first, restarts out of sight, and slides
    /// back in if it should end up visible. Takes a second or two, so call it
    /// on `queue`. Without the live slide (System Events not allowed), it
    /// falls back to a plain restart.
    static func applyOutOfSight(_ values: [String: NSObject?], animated: Bool = true) {
        guard hasChanges(values) else { return }
        // The stored hiding setting to end with: the new one if given, else the current one.
        let finalAutoHide: NSObject? = values.keys.contains("autohide")
            ? (values["autohide"] ?? nil)
            : preference("autohide")
        let endsVisible = (finalAutoHide as? NSNumber)?.boolValue != true

        guard animated, slide(hidden: true) else {
            setPreferences(values)
            return
        }
        // Restart hidden, so whatever changes happens out of sight.
        var hiddenValues = values
        hiddenValues["autohide"] = NSNumber(value: true)
        write(hiddenValues)
        restartDockAndWait()

        if endsVisible && !slide(hidden: false) {
            // The new Dock didn't slide in; bring it back with a restart instead.
            write(["autohide": finalAutoHide])
            restartDock()
            return
        }
        write(["autohide": finalAutoHide])
    }

    /// Hides the Dock again after ⌘⌥D or System Settings showed it: live if
    /// System Events is allowed, otherwise with a restart.
    static func rehide() {
        if slide(hidden: true) { return }
        setPreferences(["autohide": NSNumber(value: true)])
    }

    /// HIServices' private `CoreDockGetAutoHideEnabled`: whether the running
    /// Dock is hiding. (Its setter is refused to apps outside Apple.)
    private static let coreDockGetAutoHide: (@convention(c) () -> DarwinBoolean)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockGetAutoHideEnabled") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) () -> DarwinBoolean).self)
    }()

    /// Whether the running Dock is hidden right now, which can differ from the
    /// stored setting; nil when that can't be asked.
    static var isHiddenLive: Bool? {
        coreDockGetAutoHide.map { $0().boolValue }
    }

    /// Shows or hides the running Dock with its own slide animation, through
    /// System Events (the first use asks the user to allow it). Waits for the
    /// slide to finish; returns whether the Dock reached the requested state.
    @discardableResult
    private static func slide(hidden: Bool) -> Bool {
        guard let isHidden = isHiddenLive else { return false }
        if isHidden == hidden { return true }
        let script = Process()
        script.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        script.arguments = ["-e", "tell application \"System Events\" to set autohide of dock preferences to \(hidden)"]
        script.standardOutput = FileHandle.nullDevice
        script.standardError = FileHandle.nullDevice
        guard (try? script.run()) != nil else { return false }
        script.waitUntilExit()
        guard script.terminationStatus == 0 else { return false }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if isHiddenLive == hidden {
                Thread.sleep(forTimeInterval: 0.55)
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    /// Restarts the Dock, whose stored settings say hidden, and waits until the
    /// new Dock is up and reports itself hidden (at most three seconds).
    private static func restartDockAndWait() {
        let previous = currentDockPID()
        restartDock()
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if let pid = currentDockPID(), pid != previous, isHiddenLive == true {
                Thread.sleep(forTimeInterval: 0.2)
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private static func currentDockPID() -> pid_t? {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-U", String(getuid()), "-x", "Dock"]
        let pipe = Pipe()
        pgrep.standardOutput = pipe
        pgrep.standardError = FileHandle.nullDevice
        guard (try? pgrep.run()) != nil else { return nil }
        pgrep.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return output.split(separator: "\n").first.flatMap { pid_t($0) }
    }

    // MARK: - Writing

    private static func hasChanges(_ values: [String: NSObject?]) -> Bool {
        CFPreferencesAppSynchronize(domain)
        return values.contains { key, value in
            (CFPreferencesCopyAppValue(key as CFString, domain) as? NSObject) != value
        }
    }

    private static func write(_ values: [String: NSObject?]) {
        for (key, value) in values {
            CFPreferencesSetAppValue(key as CFString, value, domain)
        }
        CFPreferencesAppSynchronize(domain)
    }
}

extension DockItem {
    /// Parses one entry of `persistent-apps`. Returns nil for tile types a
    /// profile does not manage.
    init?(dockEntry entry: [String: Any]) {
        let tileType = entry["tile-type"] as? String ?? "file-tile"
        switch tileType {
        case "spacer-tile":
            self = .spacer(.regular)
        case "small-spacer-tile":
            self = .spacer(.small)
        case "file-tile":
            guard let tileData = entry["tile-data"] as? [String: Any],
                  let fileData = tileData["file-data"] as? [String: Any],
                  let urlString = fileData["_CFURLString"] as? String
            else { return nil }

            // Type 15 is a file URL string; anything else is a plain path.
            let urlType = fileData["_CFURLStringType"] as? Int ?? 15
            let url: URL
            if urlType == 15, let parsed = URL(string: urlString) {
                url = parsed
            } else {
                url = URL(fileURLWithPath: urlString)
            }
            let path = url.path
            let label = tileData["file-label"] as? String
                ?? FileManager.default.displayName(atPath: path)
            let bundleID = tileData["bundle-identifier"] as? String
            self = .app(AppReference(path: path, label: label, bundleIdentifier: bundleID))
        default:
            return nil
        }
    }

    /// Builds the `persistent-apps` entry for this item, or nil for item types
    /// Apple's Dock cannot hold. The Dock fills in the remaining keys
    /// (bookmark data, mod dates) itself on launch.
    func dockEntry() -> [String: Any]? {
        switch self {
        case .folder, .file, .link, .widget:
            return nil
        case .spacer(.regular):
            return ["tile-type": "spacer-tile", "tile-data": [String: Any]()]
        case .spacer(.small):
            return ["tile-type": "small-spacer-tile", "tile-data": [String: Any]()]
        case .app(let app):
            var tileData: [String: Any] = [
                "file-data": [
                    "_CFURLString": app.url.absoluteString,
                    "_CFURLStringType": 15,
                ],
                "file-label": app.label,
                "file-type": 41,
            ]
            if let bundleID = app.bundleIdentifier {
                tileData["bundle-identifier"] = bundleID
            }
            return [
                "tile-type": "file-tile",
                "tile-data": tileData,
                "GUID": Int.random(in: 1...Int(Int32.max)),
            ]
        }
    }
}
