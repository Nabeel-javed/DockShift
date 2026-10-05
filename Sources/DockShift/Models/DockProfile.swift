import AppKit
import Foundation
import SwiftUI

/// Which Dock a profile drives. macOS Dock profiles hold apps and spacers only;
/// Custom Dock profiles can also hold folders, files, links and widgets.
enum ProfileKind: String, Codable, CaseIterable {
    case macOSDock
    case customDock

    var title: String {
        switch self {
        case .macOSDock: return "macOS Dock"
        case .customDock: return "Custom Dock"
        }
    }
}

/// The two spacer sizes Apple's Dock supports (`spacer-tile` and `small-spacer-tile`).
enum SpacerSize: String, Codable, CaseIterable {
    case small
    case regular

    var title: String {
        switch self {
        case .small: return "Small spacer"
        case .regular: return "Regular spacer"
        }
    }
}

/// A pinned application.
struct AppReference: Codable, Hashable {
    var path: String
    var label: String
    var bundleIdentifier: String?

    init(path: String, label: String, bundleIdentifier: String?) {
        self.path = path
        self.label = label
        self.bundleIdentifier = bundleIdentifier
    }

    init(url: URL) {
        let path = url.path
        var name = FileManager.default.displayName(atPath: path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        self.init(path: path, label: name, bundleIdentifier: Bundle(url: url)?.bundleIdentifier)
    }

    /// File URL with a trailing slash, the form the Dock stores in `_CFURLString`.
    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    var isInstalled: Bool { FileManager.default.fileExists(atPath: path) }
}

/// A folder in a Custom Dock, with optional custom name, color and letter.
struct FolderReference: Codable, Hashable {
    var path: String
    var name: String
    var color: ProfileColor = .blue
    var letter: String = ""
    var showName: Bool = true

    init(url: URL) {
        path = url.path
        name = FileManager.default.displayName(atPath: url.path)
    }

    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
}

/// A file in a Custom Dock.
struct FileReference: Codable, Hashable {
    var path: String
    var name: String

    init(url: URL) {
        path = url.path
        name = FileManager.default.displayName(atPath: url.path)
    }

    var url: URL { URL(fileURLWithPath: path) }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
}

/// A web link in a Custom Dock. Shows the site's favicon or a chosen symbol.
struct LinkReference: Codable, Hashable {
    var urlString: String
    var name: String
    /// SF Symbol name; nil means use the website's favicon.
    var symbol: String? = nil

    var url: URL? { URL(string: urlString) }
}

/// One slot in a Dock layout.
enum DockItem: Codable, Hashable {
    case app(AppReference)
    case spacer(SpacerSize)
    case folder(FolderReference)
    case file(FileReference)
    case link(LinkReference)
    case widget(WidgetInstance)

    /// Whether Apple's Dock can hold this item.
    var isSupportedInMacOSDock: Bool {
        switch self {
        case .app, .spacer: return true
        default: return false
        }
    }
}

enum ProfileColor: String, Codable, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, yellow, green, teal, gray

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .gray: return .gray
        }
    }

    var nsColor: NSColor {
        switch self {
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .teal: return .systemTeal
        case .gray: return .systemGray
        }
    }
}

/// A saved Dock layout plus a name and color for the menu bar and editor.
struct DockProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var kind: ProfileKind = .macOSDock
    var color: ProfileColor = .blue
    var items: [DockItem] = []
    var shortcut: KeyCombo? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(name: String, kind: ProfileKind = .macOSDock, items: [DockItem] = []) {
        self.name = name
        self.kind = kind
        self.items = items
    }

    var appCount: Int {
        items.reduce(0) { count, item in
            if case .app = item { return count + 1 }
            return count
        }
    }

    // Older files predate `kind`; decode missing keys with defaults.
    private enum CodingKeys: String, CodingKey {
        case id, name, kind, color, items, shortcut, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decodeIfPresent(ProfileKind.self, forKey: .kind) ?? .macOSDock
        color = try container.decodeIfPresent(ProfileColor.self, forKey: .color) ?? .blue
        items = try container.decodeIfPresent([DockItem].self, forKey: .items) ?? []
        shortcut = try container.decodeIfPresent(KeyCombo.self, forKey: .shortcut)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}
