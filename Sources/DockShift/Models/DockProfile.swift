import AppKit
import Foundation
import SwiftUI

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

/// One slot in a Dock layout. Only apps and spacers are managed, matching what
/// a profile saves; folders, recents and other tile types are left alone.
enum DockItem: Codable, Hashable {
    case app(AppReference)
    case spacer(SpacerSize)
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

/// A saved Dock layout: pinned apps, their order and spacers, plus a name and
/// color for the menu bar and editor.
struct DockProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var color: ProfileColor = .blue
    var items: [DockItem] = []
    var shortcut: KeyCombo? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var appCount: Int {
        items.reduce(0) { count, item in
            if case .app = item { return count + 1 }
            return count
        }
    }
}
