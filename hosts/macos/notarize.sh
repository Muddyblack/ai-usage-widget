#!/usr/bin/env bash
#
# Sign AI Usage.app with a Developer ID, then have Apple notarize it, so it
# opens on any Mac without the "Open Anyway" detour. Needs a paid Apple
# Developer account; without one, skip this and the app stays ad-hoc signed.
#
#   hosts/macos/notarize.sh app    after build-app.sh: sign dist/AI Usage.app
#   hosts/macos/notarize.sh dmg F  after package-dmg.sh: sign, notarize and
#                                  staple the DMG F, then staple the app too
#
# From the environment:
#   MACOS_SIGN_IDENTITY   "Developer ID Application: Name (TEAMID)", in a
#                         keychain this user can read
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD
#                         the account notarytool signs in with (an
#                         app-specific password from account.apple.com)
set -euo pipefail

MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$MACOS_DIR/../.." && pwd)"
APP="$ROOT/dist/AI Usage.app"
ENTITLEMENTS="$MACOS_DIR/entitlements.plist"

: "${MACOS_SIGN_IDENTITY:?set MACOS_SIGN_IDENTITY}"

sign() {
    codesign --force --timestamp --options runtime --entitlements "$ENTITLEMENTS" \
        --sign "$MACOS_SIGN_IDENTITY" "$@"
}

case "${1:-}" in
    app)
        # Inside out: every library and the frozen executable, then the bundle.
        # --deep would sign in the wrong order and skip the entitlements.
        find "$APP/Contents" -type f \( -name '*.dylib' -o -name '*.so' -o -perm -u+x \) -print0 |
            while IFS= read -r -d '' file; do
                if file -b "$file" | grep -q 'Mach-O'; then
                    sign "$file"
                fi
            done
        # Qt's frameworks are bundles of their own.
        find "$APP/Contents" -type d -name '*.framework' -print0 |
            while IFS= read -r -d '' framework; do sign "$framework"; done
        sign "$APP"
        codesign --verify --strict --deep --verbose=2 "$APP"
        ;;
    dmg)
        DMG="${2:?usage: notarize.sh dmg FILE.dmg}"
        : "${APPLE_ID:?set APPLE_ID}" "${APPLE_TEAM_ID:?set APPLE_TEAM_ID}" "${APPLE_APP_PASSWORD:?set APPLE_APP_PASSWORD}"
        codesign --force --timestamp --sign "$MACOS_SIGN_IDENTITY" "$DMG"
        # Notarizing the DMG covers the app inside it as well.
        xcrun notarytool submit "$DMG" --wait \
            --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD"
        xcrun stapler staple "$DMG"
        # The ZIP ships the app on its own, so it gets the ticket too.
        xcrun stapler staple "$APP"
        spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
        ;;
    *)
        echo "usage: notarize.sh app | dmg FILE.dmg" >&2
        exit 2
        ;;
esac
