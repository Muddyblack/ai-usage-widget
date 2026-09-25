#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
METADATA="$HERE/package/metadata.json"

# Find kpackagetool6 anywhere on PATH (works on NixOS, Arch, Ubuntu, Fedora, etc.)
TOOL="$(command -v kpackagetool6 2>/dev/null || true)"
if [ -z "$TOOL" ] || [ ! -x "$TOOL" ]; then
    echo "error: kpackagetool6 not found in PATH" >&2
    echo "       Install the KDE Plasma SDK for your distro:" >&2
    echo "         NixOS/nix: nix shell nixpkgs#kdePackages.plasma-sdk" >&2
    echo "         Arch:      sudo pacman -S plasma-sdk" >&2
    echo "         Ubuntu:    sudo apt install plasma-sdk" >&2
    echo "         Fedora:    sudo dnf install plasma-sdk" >&2
    exit 1
fi

# Nix shells can inherit a newer system QT_PLUGIN_PATH than the pinned KPackage
# tool. Prefer the first libplasma package structure plugin that this tool can
# actually load; other platforms keep their existing Qt plugin environment.
case "$TOOL" in
    /nix/store/*)
        OLD_IFS="$IFS"
        IFS=:
        for data_dir in ${XDG_DATA_DIRS:-}; do
            plugin_dir="${data_dir%/share}/lib/qt-6/plugins"
            if [ -f "$plugin_dir/kf6/packagestructure/plasma_applet.so" ] && \
                QT_PLUGIN_PATH="$plugin_dir${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}" \
                "$TOOL" --list-types 2>/dev/null | grep -Fq 'plasma/plasmoids/'; then
                export QT_PLUGIN_PATH="$plugin_dir${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
                break
            fi
        done
        IFS="$OLD_IFS"
        ;;
esac

ID="$(grep -oE '"Id":[[:space:]]*"[^"]+"' "$METADATA" | head -1 | sed -E 's/.*"([^"]+)"$/\1/')"
NAME="$(grep -oE '"Name":[[:space:]]*"[^"]+"' "$METADATA" | head -1 | sed -E 's/.*"([^"]+)"$/\1/')"
TEST_ID="${ID}Test"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
PACKAGE_ROOT="$XDG_DATA_HOME/plasma/plasmoids"
mkdir -p "$PACKAGE_ROOT"

# The .mo catalogs are build output (git-ignored); compile them before copying.
"$HERE/translate/build.sh"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/$(basename "$HERE")-test.XXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT
cp -r "$HERE/package/." "$TEMP_DIR/"

sed -i "s/$ID/$TEST_ID/g" "$TEMP_DIR/metadata.json"
sed -i "s/\"Name\": \"$NAME\"/\"Name\": \"$NAME (Test)\"/g" "$TEMP_DIR/metadata.json"
# Keep the localized display names distinguishable in the widget list too.
sed -i -E 's/^(\s*"Name\[[a-zA-Z_]+\]": ")([^"]+)(")/\1\2 (Test)\3/' "$TEMP_DIR/metadata.json"

ICON_SRC="$(find "$TEMP_DIR/contents/icons" -name "${ID}.svg" | head -1)"
ICON_DST="$(dirname "$ICON_SRC")/${TEST_ID}.svg"
mv "$ICON_SRC" "$ICON_DST"
sed -i "s/${ID}/${TEST_ID}/g" "$TEMP_DIR/contents/ui/main.qml"

ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
mkdir -p "$ICON_DIR"
cp "$ICON_DST" "$ICON_DIR/$TEST_ID.svg"

# The applet's translation domain is plasma_applet_<Id>, so the bundled
# catalogs must be renamed alongside the id — otherwise the test copy silently
# falls back to English. See translate/Messages.sh and translate/build.sh.
if [ -d "$TEMP_DIR/contents/locale" ]; then
    while IFS= read -r mo; do
        mv "$mo" "${mo//$ID/$TEST_ID}"
    done < <(find "$TEMP_DIR/contents/locale" -type f -name "*${ID}*.mo")
fi

echo "Installing test version of the widget..."
if "$TOOL" -t Plasma/Applet -p "$PACKAGE_ROOT" -l 2>/dev/null | grep -q "$TEST_ID"; then
    "$TOOL" -t Plasma/Applet -p "$PACKAGE_ROOT" -u "$TEMP_DIR" 2>/dev/null
    echo "Updated existing test install."
else
    "$TOOL" -t Plasma/Applet -p "$PACKAGE_ROOT" -i "$TEMP_DIR" 2>/dev/null
    echo "Installed fresh test widget."
fi

echo ""
echo "=== Test Widget Installed! ==="
echo "Add '$NAME (Test)' to your desktop/panel, or restart plasmashell if already added:"
echo "  plasmashell --replace &"
echo ""
echo "To remove the test version:"
echo "  $TOOL -t Plasma/Applet -r $TEST_ID"
echo "  rm -f $ICON_DIR/$TEST_ID.svg"
