#!/usr/bin/env bash
#
# Compile translate/<lang>.po into the binary catalogs the plasmoid loads at
# runtime: package/contents/locale/<lang>/LC_MESSAGES/plasma_applet_<Id>.mo.
#
# The .mo files are build output, not committed: `make pack` (and so the
# release), `make view`, test_install.sh and the Nix package run this first, so
# the .plasmoid users install already carries them.
set -euo pipefail

if ! command -v msgfmt >/dev/null 2>&1; then
    echo "error: msgfmt not found — install gettext (or run inside 'nix develop')" >&2
    exit 1
fi

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$dir")"
pkg="$root/package"

id="$(grep -oE '"Id"[[:space:]]*:[[:space:]]*"[^"]+"' "$pkg/metadata.json" | head -1 | sed -E 's/.*"([^"]+)"$/\1/')"
domain="plasma_applet_$id"

shopt -s nullglob
for po in "$dir"/*.po; do
    lang="$(basename "$po" .po)"
    outdir="$pkg/contents/locale/$lang/LC_MESSAGES"
    mkdir -p "$outdir"
    msgfmt --check-format --output-file="$outdir/$domain.mo" "$po"
    echo "[i18n] $lang -> ${outdir#"$root"/}/$domain.mo"
done
shopt -u nullglob
