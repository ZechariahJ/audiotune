#!/bin/bash
# Build AudioTune and assemble a runnable menu-bar .app bundle.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-debug}"
APP="AudioTune.app"
BIN_NAME="audiotune"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$BIN_NAME"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp bundle/Info.plist "$APP/Contents/Info.plist"

echo "==> ad-hoc signing"
codesign --force --deep --sign - \
    --entitlements bundle/audiotune.entitlements \
    "$APP" 2>/dev/null || codesign --force --deep --sign - "$APP"

echo "==> done: $APP"
