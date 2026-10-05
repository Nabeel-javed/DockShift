import AppKit
import CoreGraphics

/// Hides the flicker of a Dock restart by freezing a screenshot of the Dock
/// area in a click-through overlay until the new Dock process has drawn.
/// Needs Screen Recording permission; without it, switching still works but
/// is not smooth.
@MainActor
enum DockTransition {
    private static let dockBundleID = "com.apple.dock"

    static var hasScreenCapturePermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Prompts for Screen Recording if not yet granted. Returns the new state.
    @discardableResult
    static func requestScreenCapturePermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Runs `restart` with the Dock area frozen on screen. Falls back to a
    /// plain restart when the overlay cannot be produced.
    static func perform(restart: () throws -> Void) rethrows {
        guard hasScreenCapturePermission,
              !DockLayoutInfo.isAutoHidden,
              let rect = DockLayoutInfo.dockRect(),
              let image = capture(rect)
        else {
            try restart()
            return
        }

        let previousPID = dockProcessID()
        let overlay = OverlayWindow(frame: rect, image: image)
        overlay.orderFrontRegardless()

        try restart()

        waitForNewDock(previousPID: previousPID, attempts: 0) {
            overlay.fadeOutAndClose()
        }
    }

    private static func dockProcessID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleID)
            .first?.processIdentifier
    }

    /// Polls until the Dock has relaunched, then gives it a moment to render.
    private static func waitForNewDock(previousPID: pid_t?, attempts: Int, completion: @escaping @MainActor () -> Void) {
        let current = dockProcessID()
        let relaunched = current != nil && current != previousPID
        if relaunched || attempts >= 30 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { completion() }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            waitForNewDock(previousPID: previousPID, attempts: attempts + 1, completion: completion)
        }
    }

    private static func capture(_ rect: NSRect) -> NSImage? {
        // CGWindowList uses a top-left origin on the primary display.
        guard let primary = NSScreen.screens.first else { return nil }
        let cgRect = CGRect(
            x: rect.minX,
            y: primary.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        guard let cgImage = CGWindowListCreateImage(cgRect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: rect.size)
    }
}

/// Where Apple's Dock sits on screen, derived from the gap between a screen's
/// frame and its visible frame.
enum DockLayoutInfo {
    private static let domain = "com.apple.dock" as CFString

    static var isAutoHidden: Bool {
        CFPreferencesCopyAppValue("autohide" as CFString, domain) as? Bool ?? false
    }

    /// "bottom", "left" or "right".
    static var orientation: String {
        CFPreferencesCopyAppValue("orientation" as CFString, domain) as? String ?? "bottom"
    }

    static func dockRect() -> NSRect? {
        for screen in NSScreen.screens {
            let frame = screen.frame
            let visible = screen.visibleFrame
            switch orientation {
            case "left":
                let width = visible.minX - frame.minX
                if width > 1 {
                    return NSRect(x: frame.minX, y: frame.minY, width: width, height: frame.height)
                }
            case "right":
                let width = frame.maxX - visible.maxX
                if width > 1 {
                    return NSRect(x: visible.maxX, y: frame.minY, width: width, height: frame.height)
                }
            default:
                let height = visible.minY - frame.minY
                if height > 1 {
                    return NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: height)
                }
            }
        }
        return nil
    }
}

/// Borderless, click-through window that sits just above the Dock layer.
private final class OverlayWindow: NSWindow {
    init(frame: NSRect, image: NSImage) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        contentView = imageView
    }

    func fadeOutAndClose() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.close()
        })
    }
}
