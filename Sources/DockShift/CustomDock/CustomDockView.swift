import AppKit
import SwiftUI

/// The Custom Dock's content: a translucent bar of tiles. The window may be
/// thicker than the bar so magnified tiles can grow past it.
struct CustomDockView: View {
    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var runningApps: RunningAppsMonitor
    @EnvironmentObject private var windows: WindowMonitor

    let layout: DockLayout
    let profile: DockProfile

    private var barSize: CGSize {
        layout.isVertical
            ? CGSize(width: layout.dockThickness, height: layout.dockLength)
            : CGSize(width: layout.dockLength, height: layout.dockThickness)
    }

    /// Which edge the bar hugs inside the window.
    private var barAlignment: Alignment {
        switch layout.settings.position {
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }

    var body: some View {
        ZStack(alignment: barAlignment) {
            background
                .frame(width: barSize.width, height: barSize.height)
                .clipShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
            Group {
                if layout.needsScrolling {
                    ScrollView(layout.isVertical ? .vertical : .horizontal, showsIndicators: false) {
                        tiles
                    }
                } else {
                    tiles
                }
            }
            .frame(width: barSize.width, height: barSize.height)
        }
        .frame(width: layout.dockSize.width, height: layout.dockSize.height, alignment: barAlignment)
    }

    @ViewBuilder
    private var background: some View {
        switch layout.settings.material {
        case .frosted:
            VisualEffectView(material: .popover)
        case .glass:
            VisualEffectView(material: .hudWindow)
                .opacity(0.85)
        }
    }

    private var tiles: some View {
        let axis = layout.isVertical ? Axis.vertical : .horizontal
        return AxisStack(axis: axis, spacing: layout.gap) {
            ForEach(Array(profile.items.enumerated()), id: \.offset) { index, item in
                if !layout.isHidden(item) {
                    DockTile(item: item, index: index, layout: layout, profile: profile)
                }
            }
            if layout.settings.showRunningApps {
                ForEach(runningApps.unpinned(given: profile.items), id: \.processIdentifier) { app in
                    RunningAppTile(app: app, layout: layout, profile: profile)
                }
            }
            if layout.settings.showMinimizedWindows {
                ForEach(windows.minimized) { window in
                    MinimizedWindowTile(window: window, layout: layout)
                }
            }
            if layout.settings.showTrash {
                TrashTile(layout: layout)
            }
        }
        .padding(layout.padding)
    }
}

/// HStack or VStack, chosen at runtime.
struct AxisStack<Content: View>: View {
    let axis: Axis
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if axis == .vertical {
            VStack(spacing: spacing, content: content)
        } else {
            HStack(spacing: spacing, content: content)
        }
    }
}

/// Grows a tile toward the pointer when magnification is on.
private struct Magnify: ViewModifier {
    let layout: DockLayout
    let factor: CGFloat
    @State private var hovered = false

    private var anchor: UnitPoint {
        switch layout.settings.position {
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovered && layout.settings.magnification && !layout.needsScrolling ? factor : 1, anchor: anchor)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: hovered)
            .onHover { hovered = $0 }
            .zIndex(hovered ? 1 : 0)
    }
}

// MARK: - Tiles

private struct DockTile: View {
    @EnvironmentObject private var store: ProfileStore

    let item: DockItem
    let index: Int
    let layout: DockLayout
    let profile: DockProfile

    private var isWidget: Bool {
        if case .widget = item { return true }
        return false
    }

    var body: some View {
        Group {
            switch item {
            case .app(let app):
                AppTile(app: app, layout: layout, onRemove: remove)
            case .folder(let folder):
                FolderTile(folder: folder, layout: layout, onRemove: remove)
            case .file(let file):
                FileTile(file: file, layout: layout, onRemove: remove)
            case .link(let link):
                LinkTile(link: link, layout: layout, onRemove: remove)
            case .spacer:
                Color.clear
            case .widget(let widget):
                WidgetTile(widget: widget, layout: layout, onRemove: remove, onUpdate: update)
            }
        }
        .frame(
            width: layout.isVertical ? layout.tileThickness : layout.length(of: item),
            height: layout.isVertical ? layout.length(of: item) : layout.tileThickness
        )
        .modifier(Magnify(layout: layout, factor: isWidget ? 1.08 : 1.3))
    }

    private func remove() {
        store.updateItems(of: profile.id) { items in
            if items.indices.contains(index) { items.remove(at: index) }
        }
    }

    private func update(_ widget: WidgetInstance) {
        store.updateItems(of: profile.id) { items in
            if items.indices.contains(index) { items[index] = .widget(widget) }
        }
    }
}

/// Icon with a label slot beneath, shared by app, folder, file and link tiles.
private struct IconTile<Icon: View>: View {
    let layout: DockLayout
    let label: String?
    let isRunning: Bool
    var badge: String? = nil
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        VStack(spacing: 2) {
            icon()
                .frame(
                    width: label == nil ? layout.iconSize : layout.iconSize * 0.72,
                    height: label == nil ? layout.iconSize : layout.iconSize * 0.72
                )
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(badge)
                            .font(.system(size: max(8, layout.iconSize * 0.16), weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: layout.iconSize * 0.3, minHeight: layout.iconSize * 0.3)
                            .background(Capsule().fill(.red))
                            .offset(x: layout.iconSize * 0.08, y: -layout.iconSize * 0.06)
                    }
                }
            if let label {
                Text(label)
                    .font(.system(size: max(9, layout.iconSize * 0.16)))
                    .lineLimit(1)
                    .foregroundStyle(.primary.opacity(0.85))
            }
        }
        .frame(width: layout.iconSize, height: layout.iconSize)
        .overlay(alignment: .bottom) {
            if isRunning {
                Circle()
                    .fill(.primary.opacity(0.7))
                    .frame(width: 4, height: 4)
                    .offset(y: 3)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct AppTile: View {
    @EnvironmentObject private var runningApps: RunningAppsMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var windows: WindowMonitor

    let app: AppReference
    let layout: DockLayout
    let onRemove: () -> Void

    private var running: NSRunningApplication? { runningApps.app(matching: app) }

    private var badge: String? {
        guard settings.customDock.showAppBadges else { return nil }
        return windows.badges[app.label] ?? running?.localizedName.flatMap { windows.badges[$0] }
    }

    var body: some View {
        IconTile(layout: layout, label: nil, isRunning: running != nil, badge: badge) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .interpolation(.high)
        }
        .onTapGesture(perform: open)
        .help(app.label)
        .contextMenu {
            Button("Open", action: open)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
            if let running {
                Button("Hide") { running.hide() }
                Button("Quit") { running.terminate() }
            }
            Divider()
            Button("Remove from Dock", action: onRemove)
        }
    }

    private func open() {
        if let running {
            if settings.customDock.clickFocusedAppToMinimize,
               running.bundleIdentifier == runningApps.frontmostBundleID {
                running.hide()
            } else {
                running.activate(options: [.activateIgnoringOtherApps])
            }
        } else {
            NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

private struct RunningAppTile: View {
    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var windows: WindowMonitor

    let app: NSRunningApplication
    let layout: DockLayout
    let profile: DockProfile

    var body: some View {
        IconTile(layout: layout, label: nil, isRunning: true,
                 badge: settings.customDock.showAppBadges ? app.localizedName.flatMap { windows.badges[$0] } : nil) {
            Image(nsImage: app.icon ?? NSImage())
                .resizable()
                .interpolation(.high)
        }
        .frame(width: layout.isVertical ? layout.tileThickness : layout.iconSize,
               height: layout.isVertical ? layout.iconSize : layout.tileThickness)
        .modifier(Magnify(layout: layout, factor: 1.3))
        .onTapGesture { app.activate(options: [.activateIgnoringOtherApps]) }
        .help(app.localizedName ?? "")
        .contextMenu {
            if let url = app.bundleURL {
                Button("Keep in Dock") {
                    store.updateItems(of: profile.id) { $0.append(.app(AppReference(url: url))) }
                }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            Button("Hide") { app.hide() }
            Button("Quit") { app.terminate() }
        }
    }
}

/// A minimized window, restored with a click. Shows a cached thumbnail when
/// Screen Recording allowed one to be taken; otherwise the app icon.
private struct MinimizedWindowTile: View {
    @EnvironmentObject private var windows: WindowMonitor

    let window: WindowMonitor.MinimizedWindow
    let layout: DockLayout

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: layout.iconSize * 0.16, style: .continuous)
                .fill(.primary.opacity(0.08))
            if let thumbnail = window.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: layout.iconSize * 0.12, style: .continuous))
                    .padding(layout.iconSize * 0.08)
            } else {
                VStack(spacing: 2) {
                    Image(systemName: "macwindow")
                        .font(.system(size: layout.iconSize * 0.34))
                        .foregroundStyle(.secondary)
                    Text(window.title)
                        .font(.system(size: max(8, layout.iconSize * 0.14)))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
            }
            if let icon = window.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: layout.iconSize * 0.34, height: layout.iconSize * 0.34)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(layout.iconSize * 0.06)
            }
        }
        .frame(width: layout.isVertical ? layout.tileThickness : layout.minimizedTileLength,
               height: layout.isVertical ? layout.minimizedTileLength : layout.tileThickness)
        .contentShape(Rectangle())
        .modifier(Magnify(layout: layout, factor: 1.08))
        .onTapGesture { windows.restore(window) }
        .help("\(window.appName): \(window.title)")
        .contextMenu {
            Button("Restore") { windows.restore(window) }
        }
    }
}

private struct FolderTile: View {
    let folder: FolderReference
    let layout: DockLayout
    let onRemove: () -> Void
    @State private var showContents = false

    var body: some View {
        IconTile(layout: layout, label: folder.showName ? folder.name : nil, isRunning: false) {
            FolderIcon(folder: folder)
        }
        .onTapGesture { showContents.toggle() }
        .popover(isPresented: $showContents) {
            FolderContentsView(folder: folder)
        }
        .help(folder.name)
        .contextMenu {
            Button("Browse Contents") { showContents = true }
            Button("Open in Finder") { NSWorkspace.shared.open(folder.url) }
            Divider()
            Button("Remove from Dock", action: onRemove)
        }
    }
}

private struct FolderContentsView: View {
    let folder: FolderReference

    private var entries: [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder.url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(folder.name).font(.headline)
                Spacer()
                Button("Open in Finder") { NSWorkspace.shared.open(folder.url) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            .padding(12)
            Divider()
            if entries.isEmpty {
                Text("Empty folder")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(entries, id: \.self) { url in
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                    Text(url.lastPathComponent).lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, 3)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 280)
    }
}

private struct FileTile: View {
    let file: FileReference
    let layout: DockLayout
    let onRemove: () -> Void

    var body: some View {
        IconTile(layout: layout, label: nil, isRunning: false) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                .resizable()
                .interpolation(.high)
        }
        .onTapGesture { NSWorkspace.shared.open(file.url) }
        .help(file.name)
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(file.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
            Divider()
            Button("Remove from Dock", action: onRemove)
        }
    }
}

private struct LinkTile: View {
    @EnvironmentObject private var favicons: FaviconLoader

    let link: LinkReference
    let layout: DockLayout
    let onRemove: () -> Void

    var body: some View {
        IconTile(layout: layout, label: nil, isRunning: false) {
            ZStack {
                RoundedRectangle(cornerRadius: layout.iconSize * 0.22, style: .continuous)
                    .fill(.primary.opacity(0.08))
                if link.symbol == nil, let image = favicons.icon(for: link) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .padding(layout.iconSize * 0.2)
                } else {
                    Image(systemName: link.symbol ?? "link")
                        .font(.system(size: layout.iconSize * 0.42))
                        .foregroundStyle(.primary.opacity(0.8))
                }
            }
        }
        .onTapGesture(perform: open)
        .help(link.name)
        .contextMenu {
            Button("Open", action: open)
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.urlString, forType: .string)
            }
            Divider()
            Button("Remove from Dock", action: onRemove)
        }
    }

    private func open() {
        if let url = link.url { NSWorkspace.shared.open(url) }
    }
}

private struct TrashTile: View {
    let layout: DockLayout

    private var trashURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    }

    private var isFull: Bool {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: trashURL.path)) ?? []
        return !contents.isEmpty
    }

    var body: some View {
        IconTile(layout: layout, label: nil, isRunning: false) {
            Image(nsImage: NSImage(named: isFull ? NSImage.trashFullName : NSImage.trashEmptyName) ?? NSImage())
                .resizable()
                .interpolation(.high)
        }
        .frame(width: layout.isVertical ? layout.tileThickness : layout.iconSize,
               height: layout.isVertical ? layout.iconSize : layout.tileThickness)
        .modifier(Magnify(layout: layout, factor: 1.3))
        .onTapGesture { NSWorkspace.shared.open(trashURL) }
        .help("Trash")
    }
}

/// Container for a widget: background, layout menu and configuration popover.
private struct WidgetTile: View {
    let widget: WidgetInstance
    let layout: DockLayout
    let onRemove: () -> Void
    let onUpdate: (WidgetInstance) -> Void
    @State private var showConfig = false

    private var context: WidgetContext {
        WidgetContext(instance: widget, iconSize: layout.iconSize, isVertical: layout.isVertical, update: onUpdate)
    }

    var body: some View {
        WidgetView(context: context)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: layout.iconSize * 0.22, style: .continuous)
                    .fill(.primary.opacity(widgetDrawsOwnBackground(widget.type) ? 0 : 0.07))
            )
            .clipShape(RoundedRectangle(cornerRadius: layout.iconSize * 0.22, style: .continuous))
            .contextMenu {
                if widgetHasConfiguration(widget.type) {
                    Button("Configure widget…") { showConfig = true }
                }
                if widget.type.variants.count > 1 {
                    Menu("Layout") {
                        ForEach(widget.type.variants, id: \.id) { variant in
                            Button {
                                var changed = widget
                                changed.variant = variant.id
                                onUpdate(changed)
                            } label: {
                                if variant.id == widget.variant {
                                    Label(variant.title, systemImage: "checkmark")
                                } else {
                                    Text(variant.title)
                                }
                            }
                        }
                    }
                }
                Divider()
                Button("Remove from Dock", action: onRemove)
            }
            .popover(isPresented: $showConfig) {
                WidgetConfigView(context: context)
            }
    }
}
