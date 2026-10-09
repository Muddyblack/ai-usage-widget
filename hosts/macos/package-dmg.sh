#!/usr/bin/env bash
# Package an already built app. Run from any directory on macOS.
set -euo pipefail

MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$MACOS_DIR/../.." && pwd)"
APP="$ROOT/dist/AI Usage.app"
VERSION="$(sed -nE 's/.*"Version":[[:space:]]*"([^"]+)".*/\1/p' "$ROOT/hosts/kde/metadata.json")"
# The build runs on and for one CPU (psutil has no universal wheel), so the
# name says which: Apple Silicon (arm64) or Intel (x86_64).
case "$(uname -m)" in
    arm64) ARCH=apple-silicon ;;
    *) ARCH=intel ;;
esac
OUT="$ROOT/ai-usage-macos-$VERSION-$ARCH.dmg"

if [ ! -d "$APP" ]; then
    echo "Build AI Usage.app with hosts/macos/build-app.sh first." >&2
    exit 1
fi

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/ai-usage-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/AI Usage.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Install.txt" <<'TXT'
AI Usage — Installation

1. Drag AI Usage.app to Applications.
2. Eject this disk image and open AI Usage from Applications.
3. If macOS blocks this unnotarized app, open System Settings > Privacy &
   Security, scroll to Security, and choose Open Anyway for AI Usage.
   Confirm the prompt only if you trust this download.

You do not need an Apple developer account to use this app.
https://support.apple.com/guide/mac-help/mh40616/mac
TXT
# hdiutil create fails with "Resource busy" on CI runners when Spotlight or
# diskimages-helper still holds the staging folder; retry after a short pause.
for attempt in 1 2 3 4 5; do
    if hdiutil create -volname "AI Usage" -srcfolder "$STAGING" \
        -format UDZO -ov "$OUT"; then
        break
    fi
    if [ "$attempt" -eq 5 ]; then
        echo "hdiutil create kept failing." >&2
        exit 1
    fi
    echo "hdiutil create failed (attempt $attempt); retrying..." >&2
    sleep $((attempt * 5))
done
hdiutil verify "$OUT"
echo "Built $OUT"
