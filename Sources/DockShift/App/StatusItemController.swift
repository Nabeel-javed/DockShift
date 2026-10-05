import AppKit
import Combine

/// The menu bar icon and its menu: one entry per saved Dock, then the app commands.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let store: ProfileStore
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()

    init(store: ProfileStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        StatusItemController.placeAwayFromNotchOnce()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = StatusItemController.autosaveName
        statusItem = item
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "DockShift")
            button.imagePosition = .imageLeading
        }

        Publishers.CombineLatest4(store.$profiles, store.$activeProfileID, settings.$showProfileNameInMenuBar, settings.$dockSetup)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        store.$activeCustomProfileID
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        refresh()
    }

    private static let autosaveName = "DockShift"

    /// macOS puts a new menu bar item right next to the notch, where it is the
    /// first to be hidden whenever the active app's menus need the room. The
    /// first time, place DockShift's item just left of the system items
    /// instead; ⌘-dragging it still moves it anywhere.
    private static func placeAwayFromNotchOnce() {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        guard UserDefaults.standard.object(forKey: key) == nil, let screen = NSScreen.screens.first else { return }
        let systemOwners: Set<String> = ["Control Center", "SystemUIServer", "Spotlight"]
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let systemItemXs = windows.compactMap { window -> Double? in
            guard (window[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.statusWindow)),
                  let owner = window[kCGWindowOwnerName as String] as? String, systemOwners.contains(owner),
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? Double, let y = bounds["Y"] as? Double,
                  y < 5, x >= screen.frame.minX, x < screen.frame.maxX
            else { return nil }
            return x
        }
        guard let leftmost = systemItemXs.min() else { return }
        // Preferred positions count from the right edge of the screen.
        UserDefaults.standard.set(screen.frame.maxX - leftmost + 8, forKey: key)
    }

    private func refresh() {
        let active = settings.dockSetup.usesCustomDock ? store.activeCustomProfile : store.activeProfile
        if settings.showProfileNameInMenuBar, let active {
            statusItem.button?.title = " " + active.name
        } else {
            statusItem.button?.title = ""
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        if store.profiles.isEmpty {
            let empty = NSMenuItem(title: "No saved Docks", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let macProfiles = store.profiles(of: .macOSDock)
            let customProfiles = store.profiles(of: .customDock)
            let showHeaders = !macProfiles.isEmpty && !customProfiles.isEmpty
            for (kind, group) in [(ProfileKind.macOSDock, macProfiles), (.customDock, customProfiles)] where !group.isEmpty {
                if showHeaders {
                    let header = NSMenuItem(title: kind.title, action: nil, keyEquivalent: "")
                    header.isEnabled = false
                    menu.addItem(header)
                }
                for profile in group {
                    let item = NSMenuItem(title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = profile.id
                    item.state = store.isActive(profile) ? .on : .off
                    item.image = StatusItemController.dot(for: profile.color)
                    if showHeaders { item.indentationLevel = 1 }
                    if let combo = profile.shortcut, let key = combo.menuKeyEquivalent {
                        item.keyEquivalent = key
                        item.keyEquivalentModifierMask = combo.modifierFlags
                    }
                    menu.addItem(item)
                }
            }
        }

        menu.addItem(.separator())
        let setupHeader = NSMenuItem(title: "Dock", action: nil, keyEquivalent: "")
        setupHeader.isEnabled = false
        menu.addItem(setupHeader)
        for (title, custom) in [("Use Original Dock", false), ("Use Custom Dock", true)] {
            let item = NSMenuItem(title: title, action: #selector(selectSetup(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = custom
            item.state = settings.dockSetup.usesCustomDock == custom ? .on : .off
            item.indentationLevel = 1
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(command("Manage Docks…", #selector(openEditor), key: "m"))
        menu.addItem(command("Save Current Dock as New Profile…", #selector(saveCurrentDock), key: "s"))
        menu.addItem(.separator())
        menu.addItem(command("Settings…", #selector(openSettings), key: ","))
        menu.addItem(command("About DockShift", #selector(showAbout), key: ""))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit DockShift", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    private func command(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private static func dot(for color: ProfileColor) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size, flipped: false) { rect in
            color.nsColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Actions

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        store.apply(id)
    }

    @objc private func selectSetup(_ sender: NSMenuItem) {
        guard let custom = sender.representedObject as? Bool else { return }
        settings.dockSetup = DockSetup.setup(custom: custom, keepingOriginal: settings.dockSetup == .both)
    }

    @objc private func openEditor() {
        WindowManager.shared.showEditor(store: store, settings: settings)
    }

    @objc private func openSettings() {
        WindowManager.shared.showSettings(store: store, settings: settings)
    }

    @objc private func saveCurrentDock() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Save Current Dock"
        alert.informativeText = "The apps and spacers pinned to your Dock right now will be saved as a new profile."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Name"
        field.stringValue = store.profiles.isEmpty ? "Everyday" : "Dock \(store.profiles.count + 1)"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.createFromCurrentDock(name: field.stringValue)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
