import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Custom Dock window's content: the bar, slid past the screen edge when
/// hidden, and the small handle that marks where it will appear. All of it
/// animates on Core Animation; the window itself never moves.
struct CustomDockRootView: View {
    @ObservedObject var model: CustomDockModel

    var body: some View {
        ZStack(alignment: alignment) {
            if let layout = model.layout, let profile = model.profile {
                Capsule()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: layout.isVertical ? 5 : 56, height: layout.isVertical ? 56 : 5)
                    .padding(edge, 4)
                    .opacity(model.showsHandle ? 1 : 0)
                CustomDockView(
                    layout: layout,
                    profile: profile,
                    runningApps: model.runningApps,
                    minimizedWindows: model.minimizedWindows
                )
                .padding(edge, CustomDockController.edgeInset)
                .offset(model.isRevealed ? .zero : hiddenOffset(for: layout))
                .id(profile.id)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        // Springs start moving at once and retarget smoothly if the pointer
        // changes its mind mid-slide; the hide is a touch quicker and never bounces.
        .animation(model.isRevealed
                   ? .spring(response: 0.3, dampingFraction: 0.86)
                   : .spring(response: 0.24, dampingFraction: 1.0),
                   value: model.isRevealed)
        .animation(.easeInOut(duration: 0.2), value: model.showsHandle)
    }

    private var position: DockPosition { model.layout?.settings.position ?? .bottom }

    private var alignment: Alignment {
        switch position {
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }

    private var edge: Edge.Set {
        switch position {
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }

    /// Far enough past the edge that the bar and its shadow are fully out of the window.
    private func hiddenOffset(for layout: DockLayout) -> CGSize {
        let distance = CustomDockController.edgeInset + layout.dockThickness
            + layout.magnificationHeadroom + CustomDockController.shadowRoom
        switch layout.settings.position {
        case .bottom: return CGSize(width: 0, height: distance)
        case .left: return CGSize(width: -distance, height: 0)
        case .right: return CGSize(width: distance, height: 0)
        }
    }
}

/// The Custom Dock's bar: a translucent strip of tiles. Its frame may be
/// thicker than the bar so magnified tiles can grow past it.
struct CustomDockView: View {
    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var drag: DockDragState

    let layout: DockLayout
    let profile: DockProfile
    let runningApps: [NSRunningApplication]
    let minimizedWindows: [WindowMonitor.MinimizedWindow]

    private var barSize: CGSize {
        layout.isVertical
            ? CGSize(width: layout.dockThickness, height: layout.dockLength)
            : CGSize(width: layout.dockLength, height: layout.dockThickness)
    }

    /// Which edge the bar hugs inside its frame.
    private var barAlignment: Alignment {
        switch layout.settings.position {
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }

    var body: some View {
        ZStack(alignment: barAlignment) {
            // A soft shadow drawn here rather than by the window, so it slides
            // with the bar; masked so it doesn't darken the translucent bar.
            RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.3))
                .frame(width: barSize.width, height: barSize.height)
                .blur(radius: 8)
                .offset(y: layout.isVertical ? 0 : 2)
                .mask(OutsideRoundedRect(cornerRadius: layout.cornerRadius).fill(style: FillStyle(eoFill: true)))
                .allowsHitTesting(false)
            background
                .frame(width: barSize.width, height: barSize.height)
                .clipShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
            // Right-clicking empty space (gaps, spacers) opens the DockShift menu.
            RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.001))
                .frame(width: barSize.width, height: barSize.height)
                .contextMenu { DockShiftMenuItems() }
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

    /// The profile's items with identities that survive edits, so inserting or
    /// removing one animates instead of reshuffling the rest.
    private var identifiedItems: [IdentifiedItem] {
        var seen: [String: Int] = [:]
        return profile.items.enumerated().map { index, item in
            let key = item.identity
            let occurrence = seen[key, default: 0]
            seen[key] = occurrence + 1
            return IdentifiedItem(id: "\(key)#\(occurrence)", index: index, item: item)
        }
    }

    private var tiles: some View {
        let axis = layout.isVertical ? Axis.vertical : .horizontal
        let appear = AnyTransition.scale(scale: 0.5).combined(with: .opacity)
        return AxisStack(axis: axis, spacing: layout.gap) {
            ForEach(identifiedItems) { entry in
                if !layout.isHidden(entry.item) {
                    DockTile(item: entry.item, index: entry.index, layout: layout, profile: profile)
                        .transition(appear)
                }
            }
            if layout.settings.showRunningApps {
                ForEach(runningApps, id: \.processIdentifier) { app in
                    RunningAppTile(app: app, layout: layout, profile: profile)
                        .transition(appear)
                }
            }
            if layout.settings.showMinimizedWindows {
                ForEach(minimizedWindows) { window in
                    MinimizedWindowTile(window: window, layout: layout)
                        .transition(appear)
                }
            }
            if layout.settings.showTrash {
                TrashTile(layout: layout)
            }
        }
        // Dropping on the bar pins files, apps and links, or moves a dragged tile.
        .onDrop(of: DockBarDropDelegate.acceptedTypes,
                delegate: DockBarDropDelegate(layout: layout, profile: profile, store: store, drag: drag))
        .padding(layout.padding)
    }
}

private struct IdentifiedItem: Identifiable {
    let id: String
    let index: Int
    let item: DockItem
}

extension DockItem {
    /// What identifies the item across edits: its path, link or widget id.
    var identity: String {
        switch self {
        case .app(let app): return "app:" + app.path
        case .folder(let folder): return "folder:" + folder.path
        case .file(let file): return "file:" + file.path
        case .link(let link): return "link:" + link.urlString
        case .widget(let widget): return "widget:" + widget.id.uuidString
        case .spacer(let size): return "spacer:" + size.rawValue
        }
    }
}

/// Everything around a rounded rectangle (with even-odd fill), used to keep
/// the Dock's shadow outside the bar.
private struct OutsideRoundedRect: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -60, dy: -60))
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: .continuous)
        return path
    }
}

/// The DockShift menu, offered when right-clicking an empty part of the
/// Custom Dock, so it is reachable even when the menu bar item is hidden.
struct DockShiftMenuItems: View {
    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let customDocks = store.profiles(of: .customDock)
        if customDocks.count > 1 {
            Menu("Switch Dock") {
                ForEach(customDocks) { profile in
                    Button(profile.name) { store.apply(profile.id) }
                }
            }
        }
        Button("Manage Docks…") { WindowManager.shared.showEditor(store: store, settings: settings) }
        Button("Dock Settings…") { WindowManager.shared.showSettings(store: store, settings: settings) }
        Divider()
        Button("Use Original Dock") { settings.dockSetup = .macOSOnly }
        Divider()
        Button("Quit DockShift") { NSApp.terminate(nil) }
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
    @EnvironmentObject private var drag: DockDragState

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
        .opacity(drag.draggingIndex == index ? 0.35 : 1)
        // Drag to rearrange; dropping it off the Dock removes it.
        .onDrag {
            drag.beginDrag(index: index)
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.dockShiftTile.identifier, visibility: .ownProcess) { done in
                done(Data(String(index).utf8), nil)
                return nil
            }
            return provider
        }
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

    @State private var isDropTarget = false

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
        .modifier(LaunchBounce(active: runningApps.launching.contains(app.path), layout: layout))
        .modifier(DropHighlight(active: isDropTarget, layout: layout))
        .onTapGesture(perform: open)
        .help(app.label)
        // Files dropped on an app open with it.
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            Task { @MainActor in
                let urls = await DockDrop.fileURLs(from: providers)
                guard !urls.isEmpty else { return }
                _ = try? await NSWorkspace.shared.open(urls, withApplicationAt: running?.bundleURL ?? app.url,
                                                       configuration: NSWorkspace.OpenConfiguration())
            }
            return true
        }
        .contextMenu {
            AppMenu(appURL: running?.bundleURL ?? app.url, running: running, isPinned: true,
                    open: open, togglePin: onRemove)
        }
    }

    private func open() {
        if let running, settings.customDock.clickFocusedAppToMinimize,
           running.bundleIdentifier == runningApps.frontmostBundleID {
            WindowMonitor.shared.minimizeFocusedWindow(of: running)
        } else {
            if running == nil { runningApps.markLaunching(app.path) }
            AppLauncher.open(app.url, running: running)
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
        .onTapGesture { AppLauncher.open(app.bundleURL, running: app) }
        .help(app.localizedName ?? "")
        // Drag onto the Dock's pinned section to keep it there.
        .onDrag {
            let provider = NSItemProvider()
            let path = app.bundleURL?.path ?? ""
            provider.registerDataRepresentation(forTypeIdentifier: UTType.dockShiftPinApp.identifier, visibility: .ownProcess) { done in
                done(Data(path.utf8), nil)
                return nil
            }
            return provider
        }
        .contextMenu {
            if let url = app.bundleURL {
                AppMenu(appURL: url, running: app, isPinned: false, open: {
                    AppLauncher.open(url, running: app)
                }, togglePin: {
                    store.updateItems(of: profile.id) { $0.append(.app(AppReference(url: url))) }
                })
            }
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
    @State private var isDropTarget = false

    var body: some View {
        IconTile(layout: layout, label: folder.showName ? folder.name : nil, isRunning: false) {
            FolderIcon(folder: folder)
        }
        .modifier(DropHighlight(active: isDropTarget, layout: layout))
        // Files dropped on a folder move into it.
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            let destination = folder.url
            Task { @MainActor in
                for url in await DockDrop.fileURLs(from: providers) where url.deletingLastPathComponent() != destination {
                    try? FileManager.default.moveItem(at: url, to: destination.appendingPathComponent(url.lastPathComponent))
                }
            }
            return true
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
    @State private var isDropTarget = false

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
        .modifier(DropHighlight(active: isDropTarget, layout: layout))
        .onTapGesture { NSWorkspace.shared.open(trashURL) }
        .help("Trash")
        // Files dropped on the Trash are moved to it.
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            Task { @MainActor in
                for url in await DockDrop.fileURLs(from: providers) {
                    try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }
            }
            return true
        }
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

/// The app menu, like Apple's Dock: the app's windows, then Options, Hide and Quit.
private struct AppMenu: View {
    @EnvironmentObject private var windows: WindowMonitor
    @ObservedObject private var loginItems = LoginItems.shared

    let appURL: URL
    let running: NSRunningApplication?
    let isPinned: Bool
    let open: () -> Void
    let togglePin: () -> Void

    var body: some View {
        if let running {
            let appWindows = windows.windows(of: running)
            if !appWindows.isEmpty {
                ForEach(appWindows) { window in
                    Button(window.isMinimized ? "\(window.title) (minimized)" : window.title) {
                        windows.focus(window, of: running)
                    }
                }
                Divider()
            }
        } else {
            Button("Open", action: open)
            Divider()
        }
        Menu("Options") {
            Button(isPinned ? "Remove from Dock" : "Keep in Dock", action: togglePin)
            Toggle("Open at Login", isOn: Binding(
                get: { loginItems.contains(appURL) },
                set: { loginItems.set(appURL, enabled: $0) }
            ))
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([appURL]) }
            if let running {
                Divider()
                Button("Force Quit") { running.forceTerminate() }
            }
        }
        if let running {
            Divider()
            Button(running.isHidden ? "Show" : "Hide") {
                if running.isHidden { running.unhide() } else { running.hide() }
            }
            Button("Quit") { running.terminate() }
        }
    }
}

/// Bounces an app's tile away from the screen edge while it launches.
private struct LaunchBounce: ViewModifier {
    let active: Bool
    let layout: DockLayout

    func body(content: Content) -> some View {
        if active {
            TimelineView(.animation) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate * .pi / 0.4
                let height = abs(sin(phase)) * layout.iconSize * 0.35
                content.offset(offset(for: height))
            }
        } else {
            content
        }
    }

    private func offset(for height: CGFloat) -> CGSize {
        switch layout.settings.position {
        case .bottom: return CGSize(width: 0, height: -height)
        case .left: return CGSize(width: height, height: 0)
        case .right: return CGSize(width: -height, height: 0)
        }
    }
}

/// Darkens and enlarges a tile while something is dragged over it.
private struct DropHighlight: ViewModifier {
    let active: Bool
    let layout: DockLayout

    func body(content: Content) -> some View {
        content
            .scaleEffect(active ? 1.15 : 1)
            .brightness(active ? -0.15 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: active)
    }
}
