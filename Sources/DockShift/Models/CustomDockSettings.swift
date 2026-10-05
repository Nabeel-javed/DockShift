import Foundation

/// How DockShift and Apple's Dock share the screen.
enum DockSetup: String, Codable, CaseIterable, Identifiable {
    case macOSOnly
    case both
    case customMain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .macOSOnly: return "macOS Dock only"
        case .both: return "macOS Dock + Custom Dock"
        case .customMain: return "Custom Dock as your main Dock"
        }
    }

    var detail: String {
        switch self {
        case .macOSOnly: return "Switch layouts of Apple's Dock. Widgets are not available."
        case .both: return "Keep Apple's Dock and add a separate Custom Dock with widgets."
        case .customMain: return "Apple's Dock auto-hides while DockShift runs; the Custom Dock takes its place."
        }
    }

    var showsCustomDock: Bool { self != .macOSOnly }
}

enum DockPosition: String, Codable, CaseIterable, Identifiable {
    case left, bottom, right

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var isVertical: Bool { self != .bottom }
}

enum DockMaterial: String, Codable, CaseIterable, Identifiable {
    case glass, frosted

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum DockAppearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Appearance and behaviour of the Custom Dock.
struct CustomDockSettings: Codable, Equatable {
    var position: DockPosition = .bottom
    var appearance: DockAppearance = .system
    var material: DockMaterial = .frosted
    /// 0...1, mapped to an icon size of 36...96 points.
    var size: Double = 0.4
    var autoHide: Bool = true
    var showHandleWhenHidden: Bool = true
    var desktopWidgetMode: Bool = false
    var hideWhenMacOSDockAppears: Bool = false
    var showRunningApps: Bool = true
    var showMinimizedWindows: Bool = false
    var showTrash: Bool = false
    var clickFocusedAppToMinimize: Bool = false
    var showAppBadges: Bool = true
    var magnification: Bool = false

    var iconSize: CGFloat { 36 + CGFloat(size) * 60 }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case position, appearance, material, size, autoHide, showHandleWhenHidden, desktopWidgetMode
        case hideWhenMacOSDockAppears, showRunningApps, showMinimizedWindows, showTrash
        case clickFocusedAppToMinimize, showAppBadges, magnification
    }

    // Every key is optional so settings survive new fields being added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        position = try c.decodeIfPresent(DockPosition.self, forKey: .position) ?? position
        appearance = try c.decodeIfPresent(DockAppearance.self, forKey: .appearance) ?? appearance
        material = try c.decodeIfPresent(DockMaterial.self, forKey: .material) ?? material
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? size
        autoHide = try c.decodeIfPresent(Bool.self, forKey: .autoHide) ?? autoHide
        showHandleWhenHidden = try c.decodeIfPresent(Bool.self, forKey: .showHandleWhenHidden) ?? showHandleWhenHidden
        desktopWidgetMode = try c.decodeIfPresent(Bool.self, forKey: .desktopWidgetMode) ?? desktopWidgetMode
        hideWhenMacOSDockAppears = try c.decodeIfPresent(Bool.self, forKey: .hideWhenMacOSDockAppears) ?? hideWhenMacOSDockAppears
        showRunningApps = try c.decodeIfPresent(Bool.self, forKey: .showRunningApps) ?? showRunningApps
        showMinimizedWindows = try c.decodeIfPresent(Bool.self, forKey: .showMinimizedWindows) ?? showMinimizedWindows
        showTrash = try c.decodeIfPresent(Bool.self, forKey: .showTrash) ?? showTrash
        clickFocusedAppToMinimize = try c.decodeIfPresent(Bool.self, forKey: .clickFocusedAppToMinimize) ?? clickFocusedAppToMinimize
        showAppBadges = try c.decodeIfPresent(Bool.self, forKey: .showAppBadges) ?? showAppBadges
        magnification = try c.decodeIfPresent(Bool.self, forKey: .magnification) ?? magnification
    }
}
