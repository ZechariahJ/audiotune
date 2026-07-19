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
if [ -f bundle/AppIcon.icns ]; then
    cp bundle/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Sign with a Developer ID (hardened runtime, for notarization) when
# CODESIGN_IDENTITY is set; otherwise fall back to ad-hoc for local use.
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    echo "==> signing with Developer ID + hardened runtime: $CODESIGN_IDENTITY"
    codesign --force --deep --timestamp --options runtime \
        --sign "$CODESIGN_IDENTITY" \
        --entitlements bundle/audiotune.entitlements \
        "$APP"
    codesign --verify --strict --verbose=2 "$APP"
else
    echo "==> ad-hoc signing (local only; set CODESIGN_IDENTITY to notarize)"
    codesign --force --deep --sign - \
        --entitlements bundle/audiotune.entitlements \
        "$APP" 2>/dev/null || codesign --force --deep --sign - "$APP"
fi

echo "==> done: $APP"
