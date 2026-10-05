import AppKit
import Combine
import SwiftUI

/// What the Custom Dock window shows. The controller updates it and SwiftUI
/// animates the changes on Core Animation, so the window itself never moves:
/// sliding in and out, switching profiles and resizing all stay smooth.
@MainActor
final class CustomDockModel: ObservableObject {
    @Published var layout: DockLayout?
    @Published var profile: DockProfile?
    /// Snapshots taken with the layout, so tiles and the bar's size change together.
    @Published var runningApps: [NSRunningApplication] = []
    @Published var minimizedWindows: [WindowMonitor.MinimizedWindow] = []
    @Published var isRevealed = false
    @Published var showsHandle = false
}

/// Owns the Custom Dock window: shows it when the Dock setup calls for it,
/// fits it to the active profile, and reveals it when the pointer reaches the
/// screen edge.
@MainActor
final class CustomDockController {
    /// Gap between the screen edge and the Dock.
    static let edgeInset: CGFloat = 6
    /// Room beyond the Dock for its shadow.
    static let shadowRoom: CGFloat = 24

    private let store: ProfileStore
    private let settings: AppSettings
    private let runningApps = RunningAppsMonitor()
    private let model = CustomDockModel()
    private var panel: CustomDockPanel?
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitors: [Any] = []
    private var trackingTimer: Timer?
    private var pendingHide: DispatchWorkItem?
    private var menuIsOpen = false
    /// The Dock's bar on screen when revealed, for hit testing.
    private var barRect: NSRect = .zero

    init(store: ProfileStore, settings: AppSettings) {
        self.store = store
        self.settings = settings

        Publishers.CombineLatest3(store.$profiles, store.$activeCustomProfileID, settings.$customDock)
            .map { _ in () }
            .merge(with: settings.$dockSetup.map { _ in () })
            .merge(with: runningApps.$running.map { _ in () })
            .merge(with: NowPlayingController.shared.$isAnyPlayerRunning.map { _ in () })
            .merge(with: WindowMonitor.shared.$minimized.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        // Keep the Dock up while one of its menus is open.
        NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in self?.menuIsOpen = true }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in
                self?.menuIsOpen = false
                self?.pointerMoved()
            }
            .store(in: &cancellables)

        startPointerTracking()
        refresh()
    }

    /// Takes the Dock off screen at once, e.g. while the app quits.
    func tearDown() {
        panel?.orderOut(nil)
    }

    private var shouldShow: Bool {
        settings.dockSetup.showsCustomDock && store.activeCustomProfile != nil
    }

    private var screen: NSScreen? {
        let wanted = settings.customDock.displayName
        if !wanted.isEmpty, let match = NSScreen.screens.first(where: { $0.localizedName == wanted }) {
            return match
        }
        return NSScreen.screens.first
    }

    private var autoHideActive: Bool {
        settings.customDock.autoHide && !settings.customDock.desktopWidgetMode
    }

    // MARK: - Building the Dock

    func refresh() {
        guard shouldShow, let profile = store.activeCustomProfile, let screen else {
            dismiss()
            return
        }

        let dockSettings = settings.customDock
        let running = dockSettings.showRunningApps ? runningApps.unpinned(given: profile.items) : []
        WindowMonitor.shared.configure(windows: dockSettings.showMinimizedWindows, badges: dockSettings.showAppBadges)
        let minimized = dockSettings.showMinimizedWindows ? WindowMonitor.shared.minimized : []
        var layout = DockLayout(
            settings: dockSettings,
            items: profile.items,
            extraTiles: running.count + (dockSettings.showTrash ? 1 : 0),
            maxLength: maxLength(on: screen, for: dockSettings)
        )
        layout.hiddenWidgetIDs = hiddenWidgets(in: profile.items)
        layout.minimizedTiles = minimized.count

        let panel = self.panel ?? makePanel()
        panel.appearance = appearance(for: dockSettings.appearance)
        panel.level = dockSettings.desktopWidgetMode
            ? NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        panel.contentScrolls = layout.needsScrolling

        let frame = windowFrame(for: layout, on: screen)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        barRect = barFrame(for: layout, in: frame)

        let isFirstLayout = model.layout == nil
        let switchedProfile = !isFirstLayout && model.profile?.id != profile.id
        let resized = model.layout.map {
            $0.dockLength != layout.dockLength || $0.dockThickness != layout.dockThickness
        } ?? false
        let animation: Animation? = !isFirstLayout && (switchedProfile || resized)
            ? .spring(response: 0.35, dampingFraction: 0.9)
            : nil
        withAnimation(animation) {
            model.layout = layout
            model.profile = profile
            model.runningApps = running
            model.minimizedWindows = minimized
        }

        if isFirstLayout || !panel.isVisible {
            // Appear where the pointer expects: hidden when auto-hiding, shown otherwise.
            model.isRevealed = !autoHideActive
            panel.ignoresMouseEvents = autoHideActive
        } else if !autoHideActive {
            setRevealed(true)
        }
        model.showsHandle = !model.isRevealed && autoHideActive && dockSettings.showHandleWhenHidden
        if !panel.isVisible { panel.orderFrontRegardless() }
        pointerMoved()
    }

    /// Now Playing widgets set to hide while no music app is open.
    private func hiddenWidgets(in items: [DockItem]) -> Set<UUID> {
        guard !NowPlayingController.shared.isAnyPlayerRunning else { return [] }
        return Set(items.compactMap { item in
            if case .widget(let widget) = item, widget.type == .nowPlaying,
               widget.settings["hideWhenClosed"] == "true" {
                return widget.id
            }
            return nil
        })
    }

    private func makePanel() -> CustomDockPanel {
        let panel = CustomDockPanel()
        panel.onSwitch = { [weak self] offset in
            self?.store.cycleProfile(kind: .customDock, by: offset)
        }
        let root = CustomDockRootView(model: model)
            .environmentObject(store)
            .environmentObject(settings)
            .environmentObject(runningApps)
            .environmentObject(FaviconLoader.shared)
            .environmentObject(WindowMonitor.shared)
        panel.hostingView.rootView = AnyView(root)
        self.panel = panel
        return panel
    }

    /// Slides the Dock away, then takes the window off screen.
    private func dismiss() {
        guard let panel, panel.isVisible else { return }
        setRevealed(false)
        model.showsHandle = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !self.shouldShow else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func appearance(for choice: DockAppearance) -> NSAppearance? {
        switch choice {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    private func maxLength(on screen: NSScreen, for dockSettings: CustomDockSettings) -> CGFloat {
        let margin: CGFloat = 24
        return dockSettings.position.isVertical
            ? screen.visibleFrame.height - margin * 2
            : screen.frame.width - margin * 2
    }

    /// Whether Apple's Dock occupies the same edge as the Custom Dock.
    private var appleDockOnSameEdge: Bool {
        DockLayoutInfo.orientation == settings.customDock.position.rawValue
    }

    /// The window: a transparent strip along the whole edge, deep enough for
    /// the bar, magnified tiles and the shadow. It stays put; only its content
    /// moves. Keeps clear of Apple's Dock when both are shown on one edge.
    private func windowFrame(for layout: DockLayout, on screen: NSScreen) -> NSRect {
        let depth = Self.edgeInset + layout.dockThickness + layout.magnificationHeadroom + Self.shadowRoom
        let frame = screen.frame
        let visible = screen.visibleFrame
        switch layout.settings.position {
        case .bottom:
            let appleDock = appleDockOnSameEdge ? visible.minY - frame.minY : 0
            return NSRect(x: frame.minX, y: frame.minY + appleDock, width: frame.width, height: depth)
        case .left:
            let appleDock = appleDockOnSameEdge ? visible.minX - frame.minX : 0
            return NSRect(x: frame.minX + appleDock, y: visible.minY, width: depth, height: visible.height)
        case .right:
            let appleDock = appleDockOnSameEdge ? frame.maxX - visible.maxX : 0
            return NSRect(x: frame.maxX - appleDock - depth, y: visible.minY, width: depth, height: visible.height)
        }
    }

    /// Where the bar (and room for its magnified tiles) is on screen when revealed.
    private func barFrame(for layout: DockLayout, in window: NSRect) -> NSRect {
        let depth = layout.dockThickness + layout.magnificationHeadroom
        switch layout.settings.position {
        case .bottom:
            return NSRect(x: window.midX - layout.dockLength / 2, y: window.minY + Self.edgeInset,
                          width: layout.dockLength, height: depth)
        case .left:
            return NSRect(x: window.minX + Self.edgeInset, y: window.midY - layout.dockLength / 2,
                          width: depth, height: layout.dockLength)
        case .right:
            return NSRect(x: window.maxX - Self.edgeInset - depth, y: window.midY - layout.dockLength / 2,
                          width: depth, height: layout.dockLength)
        }
    }

    // MARK: - Pointer

    private func startPointerTracking() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        // Over other apps: reveal the moment the pointer reaches the edge.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            Task { @MainActor in self?.pointerMoved() }
        }) {
            eventMonitors.append(monitor)
        }
        // Over DockShift's own windows.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            Task { @MainActor in self?.pointerMoved() }
            return event
        }) {
            eventMonitors.append(monitor)
        }
        // A slow check catches what the monitors can't see, such as the pointer
        // leaving the Dock's own window.
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pointerMoved() }
        }
    }

    private func pointerMoved() {
        guard let panel, panel.isVisible, shouldShow, let screen else { return }
        let mouse = NSEvent.mouseLocation

        // Clicks reach the Dock only over its bar; everywhere else they pass through.
        let overBar = model.isRevealed && barRect.insetBy(dx: -4, dy: -4).contains(mouse)
        if panel.ignoresMouseEvents == overBar { panel.ignoresMouseEvents = !overBar }

        guard autoHideActive else { return }

        // Make room for Apple's auto-hidden Dock when both share this edge.
        if settings.customDock.hideWhenMacOSDockAppears, settings.dockSetup == .both, appleDockOnSameEdge,
           DockBridge.isAutoHidden, isAtVeryEdge(mouse, on: screen) {
            hide(after: 0)
            return
        }

        let edge = edgeStrip(on: screen)
        let inZone = model.isRevealed
            ? barRect.insetBy(dx: -14, dy: -14).union(edge).contains(mouse)
            : edge.contains(mouse)
        if inZone || isInteracting {
            pendingHide?.cancel()
            pendingHide = nil
            setRevealed(true)
        } else if model.isRevealed {
            hide(after: 0.5)
        }
    }

    /// A popover, menu or drag that started on the Dock keeps it up.
    private var isInteracting: Bool {
        if menuIsOpen { return true }
        if model.isRevealed, NSEvent.pressedMouseButtons != 0,
           barRect.insetBy(dx: -40, dy: -40).contains(NSEvent.mouseLocation) {
            return true
        }
        return NSApp.windows.contains { window in
            window.isVisible && window !== panel && String(describing: type(of: window)).contains("Popover")
        }
    }

    /// The thin strip along the screen edge, in front of the Dock, that reveals it.
    private func edgeStrip(on screen: NSScreen) -> NSRect {
        let frame = screen.frame
        switch settings.customDock.position {
        case .bottom:
            return NSRect(x: barRect.minX - 40, y: frame.minY, width: barRect.width + 80, height: 3)
        case .left:
            return NSRect(x: frame.minX, y: barRect.minY - 40, width: 3, height: barRect.height + 80)
        case .right:
            return NSRect(x: frame.maxX - 3, y: barRect.minY - 40, width: 3, height: barRect.height + 80)
        }
    }

    private func isAtVeryEdge(_ point: NSPoint, on screen: NSScreen) -> Bool {
        let frame = screen.frame
        guard frame.insetBy(dx: -1, dy: -1).contains(point) else { return false }
        switch settings.customDock.position {
        case .bottom: return point.y <= frame.minY + 1
        case .left: return point.x <= frame.minX + 1
        case .right: return point.x >= frame.maxX - 1
        }
    }

    private func hide(after delay: TimeInterval) {
        guard pendingHide == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHide = nil
            guard self.autoHideActive, !self.isInteracting else { return }
            self.setRevealed(false)
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// The view animates the slide whenever this changes.
    private func setRevealed(_ revealed: Bool) {
        guard model.isRevealed != revealed else { return }
        model.isRevealed = revealed
        model.showsHandle = !revealed && autoHideActive && settings.customDock.showHandleWhenHidden
        if !revealed { panel?.ignoresMouseEvents = true }
    }
}

/// Borderless, non-activating panel that behaves like a Dock.
final class CustomDockPanel: NSPanel {
    let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

    /// Called with +1 or -1 when the user swipes or ⌘-scrolls to switch profiles.
    var onSwitch: ((Int) -> Void)?
    /// When the content scrolls, plain swipes scroll it and switching needs ⌘.
    var contentScrolls = false
    private var swipeAccumulator: CGFloat = 0
    private var lastSwitch = Date.distantPast

    override func scrollWheel(with event: NSEvent) {
        let wantsSwitch = event.modifierFlags.contains(.command) || (!contentScrolls && abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY))
        guard wantsSwitch else {
            super.scrollWheel(with: event)
            return
        }
        if event.phase == .began { swipeAccumulator = 0 }
        swipeAccumulator += event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
        guard abs(swipeAccumulator) > 40, Date().timeIntervalSince(lastSwitch) > 0.5 else { return }
        lastSwitch = Date()
        onSwitch?(swipeAccumulator < 0 ? 1 : -1)
        swipeAccumulator = 0
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        // The shadow is drawn by the content so it slides with the Dock.
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = hostingView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
