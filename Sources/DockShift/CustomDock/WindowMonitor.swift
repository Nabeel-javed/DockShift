import AppKit
import ApplicationServices
import Combine

/// Uses the Accessibility API for two things Apple's Dock does: listing each
/// app's minimized windows (to restore them individually) and reading the
/// badge counts Apple's Dock shows. Needs Accessibility access; thumbnails
/// additionally need Screen Recording.
@MainActor
final class WindowMonitor: ObservableObject {
    static let shared = WindowMonitor()

    struct MinimizedWindow: Identifiable {
        var id: String { "\(pid)-\(title)" }
        var pid: pid_t
        var appName: String
        var icon: NSImage?
        var title: String
        var element: AXUIElement
        var thumbnail: NSImage?
    }

    @Published private(set) var minimized: [MinimizedWindow] = []
    @Published private(set) var badges: [String: String] = [:]
    @Published private(set) var hasAccessibility = AXIsProcessTrusted()

    private var timer: AnyCancellable?
    private var thumbnailTimer: AnyCancellable?
    private var wantsWindows = false
    private var wantsBadges = false
    /// Last capture of each visible window, keyed by "pid-title", used once it is minimized.
    private var thumbnails: [String: NSImage] = [:]

    private init() {}

    func configure(windows: Bool, badges: Bool) {
        wantsWindows = windows
        wantsBadges = badges
        guard windows || badges else {
            timer = nil
            thumbnailTimer = nil
            minimized = []
            self.badges = [:]
            return
        }
        if timer == nil {
            poll()
            timer = Timer.publish(every: 2, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.poll() }
        }
        if windows, thumbnailTimer == nil, DockTransition.hasScreenCapturePermission {
            captureThumbnails()
            thumbnailTimer = Timer.publish(every: 8, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.captureThumbnails() }
        } else if !windows {
            thumbnailTimer = nil
        }
    }

    /// Re-checks without showing the system prompt.
    func refreshAccessibility() {
        hasAccessibility = AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        hasAccessibility = AXIsProcessTrustedWithOptions(options)
    }

    func restore(_ window: MinimizedWindow) {
        AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [.activateIgnoringOtherApps])
    }

    private func poll() {
        hasAccessibility = AXIsProcessTrusted()
        guard hasAccessibility else { return }
        if wantsWindows { pollWindows() }
        if wantsBadges { pollBadges() }
    }

    private func pollWindows() {
        var found: [MinimizedWindow] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.bundleIdentifier != Bundle.main.bundleIdentifier {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }
            for window in windows {
                var minimizedValue: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
                      (minimizedValue as? Bool) == true else { continue }
                var titleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
                let title = (titleValue as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (app.localizedName ?? "Window")
                let key = "\(app.processIdentifier)-\(title)"
                found.append(MinimizedWindow(pid: app.processIdentifier, appName: app.localizedName ?? "", icon: app.icon,
                                             title: title, element: window, thumbnail: thumbnails[key]))
            }
        }
        minimized = found
    }

    /// Reads "AXStatusLabel" from Apple's Dock items, which carries the badge text.
    private func pollBadges() {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let lists = childrenValue as? [AXUIElement], let list = lists.first else { return }
        var itemsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &itemsValue) == .success,
              let items = itemsValue as? [AXUIElement] else { return }
        var result: [String: String] = [:]
        for item in items {
            var titleValue: CFTypeRef?
            var labelValue: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleValue)
            AXUIElementCopyAttributeValue(item, "AXStatusLabel" as CFString, &labelValue)
            if let title = titleValue as? String, let label = labelValue as? String, !label.isEmpty {
                result[title] = label
            }
        }
        badges = result
    }

    /// Captures small images of on-screen windows so a window that gets
    /// minimized later has a thumbnail to show.
    private func captureThumbnails() {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let title = info[kCGWindowName as String] as? String, !title.isEmpty
            else { continue }
            let key = "\(pid)-\(title)"
            guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, number, [.boundsIgnoreFraming, .nominalResolution]) else { continue }
            let scale = min(1, 240 / CGFloat(image.width))
            thumbnails[key] = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale))
        }
    }
}
