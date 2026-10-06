# DockShift

Save and switch your macOS Dock layouts, or add a separate Dock with widgets.

DockShift is an open-source alternative to [Dockset](https://dockset.app). Keep one Dock for work, one for gaming, one for reading, and swap between them from the menu bar, with a keyboard shortcut, or a trackpad swipe. Or run DockShift's own Custom Dock next to (or instead of) Apple's, with apps, folders, files, links and 25+ widgets.

## Which Dock

Choose from the menu bar (**Use Original Dock** / **Use Custom Dock**) or in Settings → General:

- **Original macOS Dock**: DockShift switches layouts of Apple's Dock. Widgets need the Custom Dock.
- **Custom Dock**: DockShift's Dock replaces Apple's. Move the pointer to the screen edge and the Custom Dock appears instead. A checkbox keeps Apple's Dock visible as well, if you want both.

macOS doesn't let apps remove its Dock: the same process runs Mission Control, the app switcher, Launchpad and Spaces, and macOS restarts it if it's killed. Auto-hiding it isn't enough either: a hidden Dock still slides in when the pointer reaches its edge, on top of a Custom Dock on the same edge. So while the Custom Dock is in use, DockShift moves Apple's Dock to a side edge the Custom Dock doesn't use, shrinks it, auto-hides it with long reveal and animation times, and stops icons popping out of it. If ⌘⌥D or System Settings turns hiding off, DockShift hides it again and toggles the Custom Dock's auto-hide instead. One side effect: minimized windows fly toward that side edge. Your own Dock settings are saved first and put back when you switch to the original Dock or quit, and a small helper process puts them back if DockShift crashes or is force-quit.

## macOS Dock profiles

- Save the apps pinned to Apple's Dock, their order and spacers (small or regular) as a named, color-coded profile.
- Switch from the menu bar, with a system-wide shortcut, or (soon) a macOS Focus mode.
- Visual editor: add apps, insert spacers, drag to reorder, remove. Save without applying, or apply right away.
- **Create from Current Dock** and **Replace with Current Dock** snapshot whatever is pinned.
- **Automatically save Dock changes** syncs edits made directly in Apple's Dock back into the active profile.
- **Smooth switching** slides the Dock out and back in while it changes (asks once to control System Events).

## Custom Dock

A separate Dock on the bottom, left or right edge. Frosted or glass material, light/dark/system appearance, adjustable size, optional magnification, auto-hide with an edge handle, desktop-widget mode, and "hide when macOS Dock appears".

Put anything in it: **apps** (running indicator, badges, right-click to hide/quit/remove), **folders** (custom name, color and letter; browse contents in a popout), **files**, **links** (favicon or symbol), **spacers**, **widgets**, plus optional **running apps**, **minimized windows** (restored individually, with previews) and **Trash**.

Drag and drop works like Apple's Dock: drop files, folders, apps or web links on the Dock to pin them where they land, drag tiles to rearrange them or off the Dock to remove them, and drag a running app onto the pinned section to keep it. Files dropped on an app open with it, on a folder move into it, and on the Trash go to the Trash. Right-click an app for its open windows, Options (Keep in Dock, Open at Login, Show in Finder, Force Quit), Hide and Quit. Apps bounce while they launch.

Switch Custom Dock profiles with a two-finger swipe or ⌘-scroll on the Dock.

## Automatic switching

Settings → Automation switches Docks for you:

- **When an app is in front**, e.g. Xcode → a "Code" Dock, optionally switching back when you leave it.
- **At a time** on chosen weekdays, e.g. Work at 9:00 Monday to Friday.

## Links

Drive DockShift from Raycast, Alfred, Stream Deck, Shortcuts (Open URL) or Terminal:

| Link | Does |
|---|---|
| `dockshift://switch/Work` | Use the Dock named "Work" (or `?name=Work`) |
| `dockshift://use/custom` / `dockshift://use/original` | Use the Custom Dock / Apple's Dock |
| `dockshift://next` / `dockshift://previous` | Cycle Docks of the kind in use |
| `dockshift://manage` / `dockshift://settings` | Open Manage Docks / Settings |

## Widgets

| Category | Widgets |
|---|---|
| Clocks | Clock, World Clock, Stopwatch, Focus Timer, Time Progress, Countdown, Alarm |
| Reminders | Reminders (list / next / count), Hydration |
| Calendar | Calendar (next event, date + next event, date + agenda, date) with a join-call button |
| Sticky Notes | Sticky Note (six colors) |
| Media | Now Playing for Spotify and Music (full / mini, skip buttons) |
| System | Battery (Mac + Bluetooth devices), System Activity (numbers / rings / bars), Network, AI Usage, Shortcut, AirDrop |
| Weather | Current, conditions, hourly forecast (Open-Meteo, °C/°F, themed background) |
| Business | Stripe, Paddle, Shopify (revenue, net, MRR/ARR, orders; read-only keys in the Keychain) |
| Stocks | Stock with sparkline, Watchlist (Yahoo Finance) |

Right-click any widget for **Configure widget…**, its layout, or to remove it. Click a widget for its popout.

### AI Usage limits bridge

Token activity is read from Claude Code (`~/.claude/projects`) and Codex (`~/.codex/sessions`) session logs. Remaining allowances are shown when a tool writes `~/Library/Application Support/DockShift/ai-limits.json`:

```json
{ "claude": { "percentLeft": 72, "resetsAt": "2026-10-05T12:00:00Z" }, "codex": { "percentLeft": 54 } }
```

## Permissions

All optional, asked for only when a feature needs them: **Screen Recording** (window previews), **Accessibility** (badges, minimized windows, window lists in app menus), **Automation** of System Events (smooth switching, Open at Login), **Calendars** and **Reminders**, **Automation** (Now Playing), **Location** (Weather). No account, no telemetry; profiles live in `~/Library/Application Support/DockShift`.

## Troubleshooting

**Apple's Dock is missing or small and on the side.** DockShift restores your Dock settings when it quits, even after a crash or Force Quit. If they still weren't restored, relaunch DockShift and choose *Use Original Dock*, which puts back your exact settings, or reset them to the macOS defaults by hand:

```sh
for key in autohide autohide-delay autohide-time-modifier orientation tilesize launchanim no-bouncing; do defaults delete com.apple.dock $key 2>/dev/null; done; killall Dock
```

## Building

Requires macOS 13 Ventura or later and the Xcode Command Line Tools. Full Xcode is not needed.

```sh
scripts/build-app.sh          # release build → build/DockShift.app
scripts/build-app.sh --debug  # debug build
open build/DockShift.app
```

For development, `swift build` and `.build/debug/DockShift` also work. `DockShift --dump` prints the current Dock contents and exits. `swift scripts/make-icon.swift` regenerates the app icon.

## How Dock switching works

Apple's Dock keeps its pinned items in the `persistent-apps` array of the `com.apple.dock` preference domain. DockShift reads that array to snapshot a layout and writes it back through `cfprefsd` (the same path `defaults write` uses), then restarts the Dock. Only pinned apps and spacers are managed; folders, recents, size, position and other settings are left alone.

## Roadmap

- macOS Focus mode integration: the "Switch Dock" Focus Filter is written, but macOS only lists it once the build adds App Intents metadata, which needs Xcode.

## License

MIT. See [LICENSE](LICENSE).
