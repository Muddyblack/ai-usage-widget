#!/usr/bin/env bash
#
# Assemble the KDE Plasma widget package (what `make pack` zips into the
# .plasmoid and the KDE Store ships) from the shared sources:
#
#   hosts/kde/          metadata.json, contents/ui/main.qml, contents/config
#   ui/                 -> contents/ui/shared   (the one UI every host shows)
#   backend/            -> contents/backend     (Python package + sh tools)
#   assets/             -> contents/assets      (+ the app icon in contents/icons)
#   translate/*.po      -> contents/translate   (read at runtime by ui/js/I18n.js)
#                       -> contents/locale      (compiled .mo, for metadata names)
#
# Usage: scripts/build-kde-package.sh [OUT]   (default: build/kde)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:-$root/build/kde}"
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac

rm -rf "$out"
mkdir -p "$out"
cp -r "$root/hosts/kde/." "$out/"
mkdir -p "$out/contents/ui/shared" "$out/contents/backend" "$out/contents/assets" "$out/contents/translate" "$out/contents/icons"
cp -r "$root/ui/." "$out/contents/ui/shared/"
cp -r "$root/backend/." "$out/contents/backend/"
cp -r "$root/assets/." "$out/contents/assets/"
cp "$root/assets/icons/org.muddyblack.aiUsageWidget.svg" "$out/contents/icons/"
cp "$root"/translate/*.po "$out/contents/translate/"
find "$out" \( -name '__pycache__' -o -name '*.pyc' -o -name '*~' -o -name '*.swp' \) -prune -exec rm -rf {} +

bash "$root/translate/build.sh" "$out"
echo "assembled $out"
