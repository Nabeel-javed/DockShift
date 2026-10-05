import AppKit
import Combine
import SwiftUI

/// Owns the Custom Dock panel: shows it when the Dock setup calls for it,
/// sizes it from the active profile, and keeps it pinned to its screen edge.
@MainActor
final class CustomDockController {
    private let store: ProfileStore
    private let settings: AppSettings
    private let runningApps = RunningAppsMonitor()
    private var panel: CustomDockPanel?
    private var cancellables = Set<AnyCancellable>()

    init(store: ProfileStore, settings: AppSettings) {
        self.store = store
        self.settings = settings

        Publishers.CombineLatest3(store.$profiles, store.$activeCustomProfileID, settings.$customDock)
            .map { _ in () }
            .merge(with: settings.$dockSetup.map { _ in () })
            .merge(with: runningApps.$running.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        refresh()
    }

    private var shouldShow: Bool {
        settings.dockSetup.showsCustomDock && store.activeCustomProfile != nil
    }

    private var screen: NSScreen? { NSScreen.screens.first }

    func refresh() {
        guard shouldShow, let profile = store.activeCustomProfile, let screen else {
            panel?.orderOut(nil)
            return
        }

        let dockSettings = settings.customDock
        let extra = dockSettings.showRunningApps ? runningApps.unpinned(given: profile.items).count : 0
        let layout = DockLayout(
            settings: dockSettings,
            items: profile.items,
            extraTiles: extra + (dockSettings.showTrash ? 1 : 0),
            maxLength: maxLength(on: screen, for: dockSettings)
        )

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
        panel.hostingView.rootView = AnyView(root)

        let frame = NSRect(origin: origin(for: layout.dockSize, on: screen, settings: dockSettings), size: layout.dockSize)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> CustomDockPanel {
        let panel = CustomDockPanel()
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

    /// Bottom-left corner of the Dock, keeping clear of Apple's Dock when both
    /// sit on the same edge.
    private func origin(for size: CGSize, on screen: NSScreen, settings dockSettings: CustomDockSettings) -> CGPoint {
        let edgeInset: CGFloat = 6
        let frame = screen.frame
        let visible = screen.visibleFrame
        switch dockSettings.position {
        case .bottom:
            let appleDockHeight = DockLayoutInfo.orientation == "bottom" ? visible.minY - frame.minY : 0
            return CGPoint(x: frame.midX - size.width / 2, y: frame.minY + appleDockHeight + edgeInset)
        case .left:
            let appleDockWidth = DockLayoutInfo.orientation == "left" ? visible.minX - frame.minX : 0
            return CGPoint(x: frame.minX + appleDockWidth + edgeInset, y: visible.midY - size.height / 2)
        case .right:
            let appleDockWidth = DockLayoutInfo.orientation == "right" ? frame.maxX - visible.maxX : 0
            return CGPoint(x: frame.maxX - appleDockWidth - edgeInset - size.width, y: visible.midY - size.height / 2)
        }
    }
}

/// Borderless, non-activating panel that behaves like a Dock.
final class CustomDockPanel: NSPanel {
    let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

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
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = hostingView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
