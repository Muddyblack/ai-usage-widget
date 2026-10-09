#!/usr/bin/env bash
#
# Check the translation catalogs. Run from CI and before a release.
#
# Every catalog must compile cleanly (msgfmt --check: placeholders, plural
# forms, syntax). A language listed in translate/complete-languages must also
# be complete — an untranslated or fuzzy entry there is a string that would
# silently fall back to English. Any other language (one still being
# translated, e.g. on Weblate) only reports how far along it is: a partial
# catalog is fine, the missing strings show in English.
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
required=" $(grep -v '^#' "$dir/complete-languages" 2>/dev/null | tr '\n' ' ') "

shopt -s nullglob
status=0
for po in "$dir"/*.po; do
    lang="$(basename "$po" .po)"
    if ! msgfmt --check --output-file=/dev/null "$po"; then
        echo "[i18n] $lang: does not compile" >&2
        status=1
        continue
    fi
    # --no-wrap: a long msgid is otherwise wrapped onto 'msgid ""' and
    # continuation lines, which the pattern below would not count.
    untranslated=$(msgattrib --untranslated --no-obsolete --no-wrap "$po" | grep -cE '^msgid ".+"') || true
    fuzzy=$(msgattrib --only-fuzzy --no-obsolete --no-wrap "$po" | grep -cE '^msgid ".+"') || true
    total=$(msgattrib --no-obsolete --no-wrap "$po" | grep -cE '^msgid ".+"') || true
    if [ "$untranslated" -eq 0 ] && [ "$fuzzy" -eq 0 ]; then
        echo "[i18n] $lang: complete"
    elif [[ "$required" == *" $lang "* ]]; then
        echo "[i18n] $lang: $untranslated untranslated, $fuzzy fuzzy (listed in translate/complete-languages)" >&2
        status=1
    else
        done=$((total - untranslated - fuzzy))
        echo "[i18n] $lang: $done/$total translated (partial; missing strings show in English)"
    fi
done
shopt -u nullglob

exit "$status"
