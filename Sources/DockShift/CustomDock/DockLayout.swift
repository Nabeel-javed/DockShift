import Foundation

/// Deterministic sizing for the Custom Dock, shared by the panel (to size the
/// window) and the SwiftUI content (to size each tile). Like Apple's Dock,
/// icons shrink to fit the screen before the Dock resorts to scrolling.
struct DockLayout {
    let settings: CustomDockSettings
    let items: [DockItem]
    let extraTiles: Int
    /// Longest the Dock may be along its edge.
    let maxLength: CGFloat
    /// Widgets that asked to disappear for now (e.g. Now Playing with no player open).
    var hiddenWidgetIDs: Set<UUID> = []
    /// Minimized-window tiles appended after the items; each is wider than an icon.
    var minimizedTiles: Int = 0

    /// Smallest icon size before scrolling kicks in.
    static let minimumIconSize: CGFloat = 30

    func isHidden(_ item: DockItem) -> Bool {
        if case .widget(let widget) = item { return hiddenWidgetIDs.contains(widget.id) }
        return false
    }

    var visibleItems: [DockItem] { items.filter { !isHidden($0) } }
    var isVertical: Bool { settings.position.isVertical }

    /// The icon size after shrinking to fit.
    var iconSize: CGFloat {
        let requested = settings.iconSize
        let natural = contentLength(iconSize: requested)
        guard natural > maxLength else { return requested }
        return max(DockLayout.minimumIconSize, requested * maxLength / natural)
    }

    var gap: CGFloat { gap(for: iconSize) }
    var padding: CGFloat { padding(for: iconSize) }
    var cornerRadius: CGFloat { padding + iconSize * 0.22 }
    var minimizedTileLength: CGFloat { iconSize * 1.6 }

    /// Extra room across the Dock so magnified tiles can grow past the bar.
    var magnificationHeadroom: CGFloat { settings.magnification ? iconSize * 0.4 : 0 }

    private func gap(for size: CGFloat) -> CGFloat { max(5, size * 0.14) }
    private func padding(for size: CGFloat) -> CGFloat { max(6, size * 0.16) }

    /// Size of a tile along the Dock's main axis.
    func length(of item: DockItem) -> CGFloat {
        length(of: item, iconSize: iconSize)
    }

    private func length(of item: DockItem, iconSize size: CGFloat) -> CGFloat {
        switch item {
        case .app, .folder, .file, .link:
            return size
        case .spacer(let spacer):
            return spacer == .small ? size * 0.3 : size * 0.6
        case .widget(let widget):
            if isVertical {
                return widget.widthUnits <= 2 ? size : size * 1.6
            }
            let units = CGFloat(widget.widthUnits)
            return units * size + (units - 1) * gap(for: size)
        }
    }

    private var hasWidgets: Bool {
        visibleItems.contains { if case .widget = $0 { return true } else { return false } }
    }

    /// Size of a tile across the Dock's main axis.
    var tileThickness: CGFloat {
        isVertical && hasWidgets ? iconSize * 2 + gap : iconSize
    }

    private func contentLength(iconSize size: CGFloat) -> CGFloat {
        let visible = visibleItems
        let count = visible.count + extraTiles + minimizedTiles
        var total = padding(for: size) * 2
        total += visible.reduce(0) { $0 + length(of: $1, iconSize: size) }
        total += CGFloat(extraTiles) * size
        total += CGFloat(minimizedTiles) * size * 1.6
        if count > 1 { total += CGFloat(count - 1) * gap(for: size) }
        return total
    }

    var contentLength: CGFloat { contentLength(iconSize: iconSize) }

    var needsScrolling: Bool { contentLength > maxLength + 0.5 }

    var dockLength: CGFloat { min(contentLength, maxLength) }

    /// Thickness of the visible bar.
    var dockThickness: CGFloat { tileThickness + padding * 2 }

    /// Size of the window, including magnification headroom beyond the bar.
    var dockSize: CGSize {
        isVertical
            ? CGSize(width: dockThickness + magnificationHeadroom, height: dockLength)
            : CGSize(width: dockLength, height: dockThickness + magnificationHeadroom)
    }
}
