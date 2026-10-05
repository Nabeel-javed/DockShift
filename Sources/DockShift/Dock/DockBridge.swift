import AppKit
import Foundation

enum DockBridgeError: LocalizedError {
    case synchronizeFailed

    var errorDescription: String? {
        switch self {
        case .synchronizeFailed:
            return "macOS refused to save the Dock preferences."
        }
    }
}

/// Reads and writes Apple's Dock layout.
///
/// The Dock keeps its pinned items in the `persistent-apps` array of the
/// `com.apple.dock` preference domain. Writing goes through `cfprefsd` via
/// CFPreferences (the same route `defaults write` takes); the Dock only
/// re-reads the array when it relaunches, hence `killall Dock`.
enum DockBridge {
    private static let domain = "com.apple.dock" as CFString
    private static let appsKey = "persistent-apps" as CFString

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

    /// Replaces the pinned apps with `items` and restarts the Dock so it shows them.
    static func apply(_ items: [DockItem]) throws {
        let entries = items.compactMap { $0.dockEntry() }
        CFPreferencesSetAppValue(appsKey, entries as CFArray, domain)
        guard CFPreferencesAppSynchronize(domain) else {
            throw DockBridgeError.synchronizeFailed
        }
        restartDock()
    }

    static func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
        process.waitUntilExit()
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
