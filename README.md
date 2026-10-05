# DockShift

Save and switch your macOS Dock layouts from the menu bar.

DockShift is an open-source alternative to [Dockset](https://dockset.app). Keep one Dock for work, one for gaming, one for reading, and swap between them with a click, a keyboard shortcut, or (soon) a macOS Focus mode.

## Features

- **Dock profiles.** Save the apps pinned to your Dock, their order, and spacers (small or regular) as a named, color-coded profile.
- **Switch from the menu bar.** Click the DockShift icon and pick a Dock. The active profile's name can be shown next to the icon.
- **Keyboard shortcuts.** Assign a system-wide shortcut to each profile in Settings → Shortcuts.
- **Visual editor.** Add apps, insert spacers, drag to reorder, and remove items. Save a layout without applying it, or apply it right away.
- **Create from Current Dock / Replace with Current Dock.** Snapshot whatever is pinned right now.
- **Automatically save Dock changes.** Optional: edits you make directly in Apple's Dock are synced to the active profile.
- **Backup and restore.** Export all profiles to a JSON file and restore them on another Mac.
- **Launch at login.** No account, no network, everything stays on your Mac.

## How it works

Apple's Dock keeps its pinned items in the `persistent-apps` array of the `com.apple.dock` preference domain. DockShift reads that array to snapshot a layout and writes it back (through `cfprefsd`, the same path `defaults write` uses) to restore one, then restarts the Dock so it picks up the change. Only pinned apps and spacers are managed; folders, recents, Dock size, position and other settings are left alone.

## Building

Requires macOS 13 Ventura or later and the Xcode Command Line Tools. Full Xcode is not needed.

```sh
scripts/build-app.sh          # release build → build/DockShift.app
scripts/build-app.sh --debug  # debug build
open build/DockShift.app
```

For development you can also run `swift build` and `.build/debug/DockShift`. `DockShift --dump` prints the current Dock contents and exits.

## Roadmap

1. **Dock profiles** (this release): save, switch, edit, shortcuts, auto-save, backup.
2. **Focus modes:** switch Docks automatically with macOS Focus Filters.
3. **Custom Dock:** a separate, independent Dock with apps, folders, files, links and widgets.
4. **Widgets:** calendar, reminders, timers, now playing, system stats and more.

## License

MIT. See [LICENSE](LICENSE).
