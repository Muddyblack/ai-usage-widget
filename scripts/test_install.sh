#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"  # the repository root
METADATA="$HERE/hosts/kde/metadata.json"

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

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/$(basename "$HERE")-test.XXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT
# The package is assembled from hosts/kde, ui/, backend/ and assets/ (and the
# .mo catalogs compiled) straight into the temporary copy.
"$HERE/scripts/build-kde-package.sh" "$TEMP_DIR"

# On NixOS only: plasmashell runs with the session's PATH, which there has no
# Python, so the test copy would show "python3 missing" everywhere. Pin a store
# interpreter the way flake.nix does for the real package — this shell's
# python3 if it is a Nix one, else the flake's pinned nixpkgs python3. Every
# other system keeps the plain `python3` lookup: its session PATH has one, and
# a pinned /usr/bin/python3.x would break on the next distro upgrade.
# $PYTHON3 and Settings → Advanced → Python still win at runtime either way.
if [ -e /etc/NIXOS ] || [ -d /nix/store ]; then
    PY_PIN="$(command -v python3 2>/dev/null || true)"
    [ -n "$PY_PIN" ] && PY_PIN="$(readlink -f "$PY_PIN")"
    case "$PY_PIN" in /nix/store/*) ;; *) PY_PIN="" ;; esac
    if [ -z "$PY_PIN" ] && command -v nix >/dev/null 2>&1; then
        PY_OUT="$(nix build --no-link --print-out-paths --inputs-from "$HERE" nixpkgs#python3 2>/dev/null | head -1 || true)"
        [ -n "$PY_OUT" ] && [ -x "$PY_OUT/bin/python3" ] && PY_PIN="$PY_OUT/bin/python3"
    fi
    if [ -n "$PY_PIN" ]; then
        sed -i "s|^PY_DEFAULT=\"python3\"|PY_DEFAULT=\"$PY_PIN\"|" "$TEMP_DIR/contents/backend/sh/python-interp.sh"
        echo "Python for the test copy (Nix): $PY_PIN"
    else
        echo "warning: no Nix python3 found; set Settings → Advanced → Python in the widget" >&2
    fi
fi

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
