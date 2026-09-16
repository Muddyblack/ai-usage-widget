#!/usr/bin/env bash
#
# Build `AI Usage.app`.
#
#   scripts/build-app.sh                       universal, with the frozen backend
#   scripts/build-app.sh --arch arm64          this machine only, much faster
#   scripts/build-app.sh --skip-backend        no Python inside (development)
#
# There is no Xcode project on purpose: SwiftPM compiles the executable and
# this assembles the bundle around it, so the whole build is text files that
# review as a diff.
set -euo pipefail

MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$MACOS_DIR/.." && pwd)"
BUILD="$MACOS_DIR/.build"
APP="$BUILD/AI Usage.app"

ARCHS=(arm64 x86_64)
SKIP_BACKEND=0
while [ $# -gt 0 ]; do
    case "$1" in
        --arch) ARCHS=("$2"); shift 2 ;;
        --skip-backend) SKIP_BACKEND=1; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

VERSION="$(grep -oE '"Version":[[:space:]]*"[^"]+"' "$ROOT/package/metadata.json" | head -1 | sed -E 's/.*"([^"]+)"$/\1/')"
echo "▸ AI Usage $VERSION for ${ARCHS[*]}"

# ── 1. The executable ────────────────────────────────────────────────────
SWIFT_ARGS=(build -c release --package-path "$MACOS_DIR")
for arch in "${ARCHS[@]}"; do SWIFT_ARGS+=(--arch "$arch"); done
swift "${SWIFT_ARGS[@]}"
BIN_PATH="$(swift "${SWIFT_ARGS[@]}" --show-bin-path)"

# ── 2. The bundle ────────────────────────────────────────────────────────
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/AIUsage" "$APP/Contents/MacOS/AIUsage"
cp "$ROOT/package/contents/icons/LICENSE.lobehub" "$APP/Contents/Resources/LICENSE.lobehub"
sed "s/__VERSION__/$VERSION/g" "$MACOS_DIR/Resources/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# ── 3. Artwork ───────────────────────────────────────────────────────────
# The provider logos are the widget's own SVGs. An asset catalog is the one
# way to get them into an app as vectors without a third-party renderer:
# actool ships with Xcode and keeps the vector representation, so one file
# draws crisply at 16 points in the menu bar and at 32 in the popover.
CATALOG="$BUILD/Assets.xcassets"
rm -rf "$CATALOG"
mkdir -p "$CATALOG"
cat > "$CATALOG/Contents.json" <<'JSON'
{"info":{"author":"xcode","version":1}}
JSON
for svg in "$ROOT/package/contents/icons/"*.svg; do
    name="$(basename "$svg" .svg)"
    set="$CATALOG/$name.imageset"
    mkdir -p "$set"
    cp "$svg" "$set/$name.svg"
    cat > "$set/Contents.json" <<JSON
{
  "images": [{"filename": "$name.svg", "idiom": "universal"}],
  "info": {"author": "xcode", "version": 1},
  "properties": {"preserves-vector-representation": true, "template-rendering-intent": "original"}
}
JSON
done
if ! xcrun actool "$CATALOG" \
    --compile "$APP/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --output-format human-readable-text > "$BUILD/actool.log" 2>&1; then
    echo "actool failed:" >&2
    cat "$BUILD/actool.log" >&2
    exit 1
fi

# The app icon needs a raster source, and nothing in macOS rasterises SVG from
# the command line. Missing one costs the Finder icon and nothing else, so it
# is a warning rather than a failed build.
if command -v rsvg-convert >/dev/null 2>&1; then
    ICONSET="$BUILD/AppIcon.iconset"
    rm -rf "$ICONSET"; mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        rsvg-convert -w "$size" -h "$size" "$ROOT/package/contents/icons/org.muddyblack.aiUsageWidget.svg" \
            -o "$ICONSET/icon_${size}x${size}.png"
        rsvg-convert -w "$((size * 2))" -h "$((size * 2))" "$ROOT/package/contents/icons/org.muddyblack.aiUsageWidget.svg" \
            -o "$ICONSET/icon_${size}x${size}@2x.png"
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
else
    echo "  note: rsvg-convert not found (brew install librsvg) — no .icns, Finder shows the generic icon"
fi

# ── 4. Translations ──────────────────────────────────────────────────────
# The .po files themselves, not compiled .mo: the app parses them at runtime
# (Catalog.swift), exactly as the Quickshell panel and the Windows tray app do,
# so there is one set of catalogs for every frontend.
mkdir -p "$APP/Contents/Resources/translate"
cp "$ROOT"/translate/*.po "$APP/Contents/Resources/translate/" 2>/dev/null || \
    echo "  note: no translate/*.po found — the app will be English only"

# ── 5. The backend ───────────────────────────────────────────────────────
if [ "$SKIP_BACKEND" -eq 0 ]; then
    echo "▸ freezing the Python backend"
    ( cd "$MACOS_DIR/packaging" && pyinstaller --noconfirm --distpath "$BUILD/backend-dist" \
        --workpath "$BUILD/backend-work" ai-usage-backend.spec )
    rm -rf "$APP/Contents/Resources/backend"
    cp -R "$BUILD/backend-dist/backend" "$APP/Contents/Resources/backend"
else
    echo "  note: --skip-backend — the app will fall back to the checkout's get-ai-usage"
fi

# ── 6. Signature ─────────────────────────────────────────────────────────
# Ad-hoc unless an identity is given. Ad-hoc is enough to run — reading the
# Keychain goes through /usr/bin/security, which does not care what this app is
# signed with — but Gatekeeper requires a first-launch exception through
# System Settings → Privacy & Security → Open Anyway. See docs/macos.md.
IDENTITY="${AI_USAGE_SIGN_IDENTITY:--}"
codesign --force --deep --sign "$IDENTITY" --options runtime --timestamp=none "$APP" 2>/dev/null \
    || codesign --force --deep --sign "$IDENTITY" "$APP"

echo "▸ built $APP"
