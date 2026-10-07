#!/usr/bin/env bash
#
# Build `AI Usage.app` (macOS only): the shared tray app and UI, frozen by
# PyInstaller (hosts/macos/ai-usage.spec), with the native menu bar item.
#
#   hosts/macos/build-app.sh            -> dist/AI Usage.app
#
# Needs: pip install -r hosts/macos/build-requirements.txt
# Optional: rsvg-convert (brew install librsvg) for the Finder icon.
set -euo pipefail

MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$MACOS_DIR/../.." && pwd)"
BUILD="$ROOT/build/macos"
mkdir -p "$BUILD"

# The app icon needs a raster source, and nothing in macOS rasterises SVG from
# the command line. Missing one costs the Finder icon and nothing else.
if command -v rsvg-convert >/dev/null 2>&1; then
    ICONSET="$BUILD/AppIcon.iconset"
    rm -rf "$ICONSET"; mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        rsvg-convert -w "$size" -h "$size" "$ROOT/assets/icons/org.muddyblack.aiUsageWidget.svg" \
            -o "$ICONSET/icon_${size}x${size}.png"
        rsvg-convert -w "$((size * 2))" -h "$((size * 2))" "$ROOT/assets/icons/org.muddyblack.aiUsageWidget.svg" \
            -o "$ICONSET/icon_${size}x${size}@2x.png"
    done
    iconutil -c icns "$ICONSET" -o "$BUILD/AppIcon.icns"
    export AI_USAGE_ICNS="$BUILD/AppIcon.icns"
else
    echo "  note: rsvg-convert not found (brew install librsvg) — no .icns, Finder shows the generic icon"
fi

cd "$ROOT"
pyinstaller --noconfirm --workpath "$BUILD/pyinstaller" --distpath "$ROOT/dist" hosts/macos/ai-usage.spec
cp "$ROOT/assets/icons/LICENSE.lobehub" "$ROOT/dist/AI Usage.app/Contents/Resources/LICENSE.lobehub"
echo "Built $ROOT/dist/AI Usage.app"
