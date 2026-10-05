# DockShift

Save and switch your macOS Dock layouts, or add a separate Dock with widgets.

DockShift is an open-source alternative to [Dockset](https://dockset.app). Keep one Dock for work, one for gaming, one for reading, and swap between them from the menu bar, with a keyboard shortcut, or a trackpad swipe. Or run DockShift's own Custom Dock next to (or instead of) Apple's, with apps, folders, files, links and 25+ widgets.

## Dock setup

Pick how DockShift and Apple's Dock share the screen in Settings → Custom Dock:

| Setup | What it does |
|---|---|
| **macOS Dock only** | Switch layouts of Apple's Dock. No widgets. |
| **macOS Dock + Custom Dock** | Keep Apple's Dock and add a separate Custom Dock on another edge. |
| **Custom Dock as your main Dock** | Apple's Dock auto-hides while DockShift runs; the Custom Dock takes its place. |

## macOS Dock profiles

- Save the apps pinned to Apple's Dock, their order and spacers (small or regular) as a named, color-coded profile.
- Switch from the menu bar, with a system-wide shortcut, or (soon) a macOS Focus mode.
- Visual editor: add apps, insert spacers, drag to reorder, remove. Save without applying, or apply right away.
- **Create from Current Dock** and **Replace with Current Dock** snapshot whatever is pinned.
- **Automatically save Dock changes** syncs edits made directly in Apple's Dock back into the active profile.
- **Smooth switching** freezes a snapshot of the Dock while it restarts (needs Screen Recording).

## Custom Dock

A separate Dock on the bottom, left or right edge. Frosted or glass material, light/dark/system appearance, adjustable size, optional magnification, auto-hide with an edge handle, desktop-widget mode, and "hide when macOS Dock appears".

Put anything in it: **apps** (running indicator, badges, right-click to hide/quit/remove), **folders** (custom name, color and letter; browse contents in a popout), **files**, **links** (favicon or symbol), **spacers**, **widgets**, plus optional **running apps**, **minimized windows** (restored individually, with previews) and **Trash**.

Switch Custom Dock profiles with a two-finger swipe or ⌘-scroll on the Dock.

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

All optional, asked for only when a feature needs them: **Screen Recording** (smooth switching, window previews), **Accessibility** (badges, minimized windows), **Calendars** and **Reminders**, **Automation** (Now Playing), **Location** (Weather). No account, no telemetry; profiles live in `~/Library/Application Support/DockShift`.

## Troubleshooting

**Apple's Dock stays hidden after DockShift crashed.** In "Use Custom Dock" mode DockShift hides Apple's Dock and gives it a very long reveal delay, restoring both when the mode changes or it quits. If it was force-quit, relaunch DockShift and pick *Use macOS Dock*, or run:

```sh
defaults delete com.apple.dock autohide-delay; defaults write com.apple.dock autohide -bool false; killall Dock
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

- macOS Focus mode integration (Focus Filters)
- First-run walkthrough
- Choosing the display for the Custom Dock

## License

MIT. See [LICENSE](LICENSE).
