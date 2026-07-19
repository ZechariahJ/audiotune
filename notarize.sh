#!/bin/bash
# Notarize and staple AudioTune.app.
#
# Prerequisites (one-time):
#   1. Apple Developer Program membership ($99/yr).
#   2. A "Developer ID Application" certificate in your login keychain
#      (create at developer.apple.com > Certificates, or via Xcode > Settings >
#       Accounts > Manage Certificates). Confirm with:
#          security find-identity -v -p codesigning
#   3. Store notarization credentials once as a keychain profile:
#          xcrun notarytool store-credentials audiotune-notary \
#              --apple-id "you@example.com" \
#              --team-id "YOURTEAMID" \
#              --password "app-specific-password"   # from appleid.apple.com
#
# Then build signed + notarize:
#          CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh release
#          ./notarize.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="AudioTune.app"
PROFILE="${NOTARY_PROFILE:-audiotune-notary}"
ZIP="AudioTune-notarize.zip"

if [ ! -d "$APP" ]; then
    echo "error: $APP not found. Build it first with a Developer ID:"
    echo '  CODESIGN_IDENTITY="Developer ID Application: ... (TEAMID)" ./build.sh release'
    exit 1
fi

# Guard against submitting an ad-hoc-signed app (notarization would reject it).
if ! codesign -dv --verbose=4 "$APP" 2>&1 | grep -q "Authority=Developer ID Application"; then
    echo "error: $APP is not signed with a Developer ID Application certificate."
    echo "       Rebuild with CODESIGN_IDENTITY set (see this script's header)."
    exit 1
fi

echo "==> zipping for submission"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> submitting to Apple notary service (profile: $PROFILE)"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "==> stapling ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
rm -f "$ZIP"

echo "==> notarized + stapled: $APP"
echo "    Gatekeeper check:"
spctl --assess --type execute --verbose=4 "$APP" || true
