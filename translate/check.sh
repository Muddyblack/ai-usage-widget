#!/usr/bin/env bash
#
# Fail when a catalog is incomplete: an untranslated or fuzzy entry is a string
# that would silently fall back to English in the UI. Run from CI and before a
# release.
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

shopt -s nullglob
status=0
for po in "$dir"/*.po; do
    lang="$(basename "$po" .po)"
    untranslated=$(msgattrib --untranslated --no-obsolete "$po" | grep -cE '^msgid ".+"') || true
    fuzzy=$(msgattrib --only-fuzzy --no-obsolete "$po" | grep -cE '^msgid ".+"') || true
    if [ "$untranslated" -gt 0 ] || [ "$fuzzy" -gt 0 ]; then
        echo "[i18n] $lang: $untranslated untranslated, $fuzzy fuzzy" >&2
        status=1
    else
        echo "[i18n] $lang: complete"
    fi
done
shopt -u nullglob

exit "$status"
