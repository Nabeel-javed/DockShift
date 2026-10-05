import AppKit
import Carbon

/// A keyboard shortcut stored in Carbon terms, since global hotkeys are
/// registered with `RegisterEventHotKey`.
struct KeyCombo: Codable, Hashable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var keyLabel: String

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.isEmpty else { return nil }
        keyCode = UInt32(event.keyCode)
        carbonModifiers = KeyCombo.carbonFlags(from: flags)
        keyLabel = KeyCombo.label(for: event)
    }

    /// Human-readable form, e.g. "⌃⌥1".
    var display: String {
        var text = ""
        if carbonModifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyLabel
    }

    /// Modifier flags in AppKit terms, for showing the shortcut on menu items.
    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    /// The key equivalent string for an NSMenuItem, when the key is a plain character.
    var menuKeyEquivalent: String? {
        keyLabel.count == 1 ? keyLabel.lowercased() : nil
    }

    static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func label(for event: NSEvent) -> String {
        if let special = specialKeys[Int(event.keyCode)] { return special }
        let chars = event.charactersIgnoringModifiers ?? ""
        return chars.isEmpty ? "?" : chars.uppercased()
    }
}
