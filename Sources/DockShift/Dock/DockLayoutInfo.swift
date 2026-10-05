import AppKit
import CoreGraphics

/// Where Apple's Dock sits.
enum DockLayoutInfo {
    private static let domain = "com.apple.dock" as CFString

    /// "bottom", "left" or "right".
    static var orientation: String {
        CFPreferencesCopyAppValue("orientation" as CFString, domain) as? String ?? "bottom"
    }
}

/// Screen Recording access, used for minimized-window previews.
enum ScreenCapture {
    static var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }
}
