import AppKit
import Combine
import SwiftUI

/// Owns the Custom Dock panel: shows it when the Dock setup calls for it,
/// sizes it from the active profile, keeps it pinned to its screen edge, and
/// slides it away when auto-hide is on.
@MainActor
final class CustomDockController {
    private let store: ProfileStore
    private let settings: AppSettings
    private let runningApps = RunningAppsMonitor()
    private var panel: CustomDockPanel?
    private var handle: HandleWindow?
    private var cancellables = Set<AnyCancellable>()

    /// Frame of the Dock when fully shown; the hidden frame is derived from it.
    private var shownFrame: NSRect = .zero
    private var isHidden = false
    private var pointerTimer: Timer?
    private var pendingHide: DispatchWorkItem?

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

        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkPointer() }
        }

        refresh()
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
            panel?.orderOut(nil)
            handle?.orderOut(nil)
            return
        }

        let dockSettings = settings.customDock
        let extra = dockSettings.showRunningApps ? runningApps.unpinned(given: profile.items).count : 0
        var layout = DockLayout(
            settings: dockSettings,
            items: profile.items,
            extraTiles: extra + (dockSettings.showTrash ? 1 : 0),
            maxLength: maxLength(on: screen, for: dockSettings)
        )
        layout.hiddenWidgetIDs = hiddenWidgets(in: profile.items)
        WindowMonitor.shared.configure(windows: dockSettings.showMinimizedWindows, badges: dockSettings.showAppBadges)
        layout.minimizedTiles = dockSettings.showMinimizedWindows ? WindowMonitor.shared.minimized.count : 0

        let panel = self.panel ?? makePanel()
        panel.appearance = appearance(for: dockSettings.appearance)
        panel.level = dockSettings.desktopWidgetMode
            ? NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))

        let root = CustomDockView(layout: layout, profile: profile)
            .environmentObject(store)
            .environmentObject(settings)
            .environmentObject(runningApps)
            .environmentObject(FaviconLoader.shared)
            .environmentObject(WindowMonitor.shared)
        panel.hostingView.rootView = AnyView(root)
        panel.contentScrolls = layout.needsScrolling

        shownFrame = NSRect(origin: origin(for: layout.dockSize, on: screen, settings: dockSettings), size: layout.dockSize)
        if !autoHideActive { isHidden = false }
        panel.setFrame(isHidden ? hiddenFrame(on: screen) : shownFrame, display: true)
        panel.orderFrontRegardless()
        updateHandle(on: screen)
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
        self.panel = panel
        return panel
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

    /// Bottom-left corner of the Dock, keeping clear of Apple's Dock when both
    /// sit on the same edge.
    private func origin(for size: CGSize, on screen: NSScreen, settings dockSettings: CustomDockSettings) -> CGPoint {
        let edgeInset: CGFloat = 6
        let frame = screen.frame
        let visible = screen.visibleFrame
        switch dockSettings.position {
        case .bottom:
            let appleDockHeight = appleDockOnSameEdge ? visible.minY - frame.minY : 0
            return CGPoint(x: frame.midX - size.width / 2, y: frame.minY + appleDockHeight + edgeInset)
        case .left:
            let appleDockWidth = appleDockOnSameEdge ? visible.minX - frame.minX : 0
            return CGPoint(x: frame.minX + appleDockWidth + edgeInset, y: visible.midY - size.height / 2)
        case .right:
            let appleDockWidth = appleDockOnSameEdge ? frame.maxX - visible.maxX : 0
            return CGPoint(x: frame.maxX - appleDockWidth - edgeInset - size.width, y: visible.midY - size.height / 2)
        }
    }

    /// The Dock's frame when slid off screen (a little extra so its shadow goes too).
    private func hiddenFrame(on screen: NSScreen) -> NSRect {
        var frame = shownFrame
        let overshoot: CGFloat = 12
        switch settings.customDock.position {
        case .bottom: frame.origin.y = screen.frame.minY - frame.height - overshoot
        case .left: frame.origin.x = screen.frame.minX - frame.width - overshoot
        case .right: frame.origin.x = screen.frame.maxX + overshoot
        }
        return frame
    }

    // MARK: - Auto-hide

    private func checkPointer() {
        guard shouldShow, let screen, panel != nil else { return }
        guard autoHideActive else {
            if isHidden { reveal(on: screen) }
            return
        }

        let mouse = NSEvent.mouseLocation
        let dockSettings = settings.customDock

        // Make room for Apple's auto-hidden Dock when it is about to appear on our edge.
        if dockSettings.hideWhenMacOSDockAppears, appleDockOnSameEdge, DockBridge.isAutoHidden,
           isAtVeryEdge(mouse, on: screen) {
            scheduleHide(after: 0)
            return
        }

        if revealZone(on: screen).contains(mouse) {
            pendingHide?.cancel()
            pendingHide = nil
            if isHidden { reveal(on: screen) }
        } else if !isHidden {
            scheduleHide(after: 0.6)
        }
    }

    /// The shown Dock plus a thin strip along the screen edge in front of it.
    private func revealZone(on screen: NSScreen) -> NSRect {
        let around = shownFrame.insetBy(dx: -14, dy: -14)
        let frame = screen.frame
        let strip: NSRect
        switch settings.customDock.position {
        case .bottom:
            strip = NSRect(x: shownFrame.minX - 40, y: frame.minY, width: shownFrame.width + 80, height: 3)
        case .left:
            strip = NSRect(x: frame.minX, y: shownFrame.minY - 40, width: 3, height: shownFrame.height + 80)
        case .right:
            strip = NSRect(x: frame.maxX - 3, y: shownFrame.minY - 40, width: 3, height: shownFrame.height + 80)
        }
        return around.union(strip)
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

    private func scheduleHide(after delay: TimeInterval) {
        guard pendingHide == nil, let screen else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHide = nil
            self.hide(on: screen)
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func reveal(on screen: NSScreen) {
        isHidden = false
        animate(panel, to: shownFrame)
        updateHandle(on: screen)
    }

    private func hide(on screen: NSScreen) {
        guard autoHideActive, !isHidden else { return }
        isHidden = true
        animate(panel, to: hiddenFrame(on: screen))
        updateHandle(on: screen)
    }

    private func animate(_ panel: NSPanel?, to frame: NSRect) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func updateHandle(on screen: NSScreen) {
        let wantHandle = isHidden && autoHideActive && settings.customDock.showHandleWhenHidden
        guard wantHandle else {
            handle?.orderOut(nil)
            return
        }
        let handle = self.handle ?? HandleWindow()
        self.handle = handle
        handle.appearance = panel?.appearance
        handle.setFrame(handleFrame(on: screen), display: true)
        handle.orderFrontRegardless()
    }

    private func handleFrame(on screen: NSScreen) -> NSRect {
        let frame = screen.frame
        let length: CGFloat = 56
        let thickness: CGFloat = 6
        let inset: CGFloat = 4
        switch settings.customDock.position {
        case .bottom:
            return NSRect(x: shownFrame.midX - length / 2, y: frame.minY + inset, width: length, height: thickness)
        case .left:
            return NSRect(x: frame.minX + inset, y: shownFrame.midY - length / 2, width: thickness, height: length)
        case .right:
            return NSRect(x: frame.maxX - inset - thickness, y: shownFrame.midY - length / 2, width: thickness, height: length)
        }
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
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = hostingView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The small pill shown at the screen edge while the Dock is hidden.
final class HandleWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 56, height: 6),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = NSHostingView(rootView:
            Capsule().fill(.primary.opacity(0.35))
        )
    }
}
