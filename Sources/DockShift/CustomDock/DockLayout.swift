import Foundation

/// Deterministic sizing for the Custom Dock, shared by the panel (to size the
/// window) and the SwiftUI content (to size each tile).
struct DockLayout {
    let settings: CustomDockSettings
    let items: [DockItem]
    let extraTiles: Int
    /// Longest the Dock may be along its edge before it scrolls.
    let maxLength: CGFloat
    /// Widgets that asked to disappear for now (e.g. Now Playing with no player open).
    var hiddenWidgetIDs: Set<UUID> = []

    func isHidden(_ item: DockItem) -> Bool {
        if case .widget(let widget) = item { return hiddenWidgetIDs.contains(widget.id) }
        return false
    }

    var visibleItems: [DockItem] { items.filter { !isHidden($0) } }

    var iconSize: CGFloat { settings.iconSize }
    var gap: CGFloat { max(6, iconSize * 0.14) }
    var padding: CGFloat { max(8, iconSize * 0.16) }
    var cornerRadius: CGFloat { padding + iconSize * 0.22 }
    var isVertical: Bool { settings.position.isVertical }

    /// Size of a tile along the Dock's main axis.
    func length(of item: DockItem) -> CGFloat {
        switch item {
        case .app, .folder, .file, .link:
            return iconSize
        case .spacer(let size):
            return size == .small ? iconSize * 0.3 : iconSize * 0.6
        case .widget(let widget):
            if isVertical {
                return widget.widthUnits <= 2 ? iconSize : iconSize * 1.6
            }
            let units = CGFloat(widget.widthUnits)
            return units * iconSize + (units - 1) * gap
        }
    }

    /// Size of a tile across the Dock's main axis.
    var tileThickness: CGFloat {
        let hasWidgets = items.contains { if case .widget = $0 { return true } else { return false } }
        return isVertical && hasWidgets ? iconSize * 2 + gap : iconSize
    }

    var contentLength: CGFloat {
        var total = padding * 2
        let visible = visibleItems
        let all = visible.count + extraTiles
        total += visible.reduce(0) { $0 + length(of: $1) }
        total += CGFloat(extraTiles) * iconSize
        if all > 1 { total += CGFloat(all - 1) * gap }
        return total
    }

    var needsScrolling: Bool { contentLength > maxLength }

    var dockLength: CGFloat { min(contentLength, maxLength) }
    var dockThickness: CGFloat { tileThickness + padding * 2 }

    var dockSize: CGSize {
        isVertical
            ? CGSize(width: dockThickness, height: dockLength)
            : CGSize(width: dockLength, height: dockThickness)
    }
}
