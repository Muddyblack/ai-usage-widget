#!/usr/bin/env bash
# Package an already built app. Run from any directory on macOS.
set -euo pipefail

MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$MACOS_DIR/.." && pwd)"
APP="$MACOS_DIR/.build/AI Usage.app"
VERSION="$(sed -nE 's/.*"Version":[[:space:]]*"([^"]+)".*/\1/p' "$ROOT/package/metadata.json")"
OUT="$ROOT/ai-usage-macos-$VERSION.dmg"

if [ ! -d "$APP" ]; then
    echo "Build AI Usage.app with macos/scripts/build-app.sh first." >&2
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
hdiutil create -volname "AI Usage" -srcfolder "$STAGING" \
    -format UDZO -ov "$OUT"
hdiutil verify "$OUT"
echo "Built $OUT"
