#!/bin/bash
# Builds DockShift with SwiftPM and assembles a runnable .app bundle.
# Requires only the Xcode Command Line Tools.
#
#   scripts/build-app.sh            release build -> build/DockShift.app
#   scripts/build-app.sh --debug    debug build
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG=release
if [[ "${1:-}" == "--debug" ]]; then
  CONFIG=debug
fi

swift build -c "$CONFIG"

APP="build/DockShift.app"
BIN=".build/$CONFIG/DockShift"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DockShift"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc signature so macOS keeps TCC permissions stable between rebuilds.
codesign --force --sign - --identifier com.dockshift.DockShift "$APP" >/dev/null

echo "Built $APP"
