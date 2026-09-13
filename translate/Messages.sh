#!/usr/bin/env bash
#
# Extract every translatable string from the plasmoid and merge it into the
# per-language catalogs under translate/.
#
# The widget ships its own translations inside the .plasmoid archive, in
# package/contents/locale/<lang>/LC_MESSAGES/plasma_applet_<Id>.mo. This script
# only produces the sources of truth: translate/template.pot and translate/*.po.
# build.sh compiles the .mo files; they are git-ignored build output.
#
# Requires gettext (xgettext, msgmerge). Everything is self-contained — no CMake
# or KF6 tree needed, so the Nix build and a plain checkout behave the same.
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$dir")"
pkg="$root/package"

id="$(grep -oE '"Id"[[:space:]]*:[[:space:]]*"[^"]+"' "$pkg/metadata.json" | head -1 | sed -E 's/.*"([^"]+)"$/\1/')"
version="$(grep -oE '"Version"[[:space:]]*:[[:space:]]*"[^"]+"' "$pkg/metadata.json" | head -1 | sed -E 's/.*"([^"]+)"$/\1/')"
bug_url="$(grep -oE '"Website"[[:space:]]*:[[:space:]]*"[^"]+"' "$pkg/metadata.json" | head -1 | sed -E 's/.*"([^"]+)"$/\1/')"

if [ -z "$id" ]; then
    echo "error: could not read KPlugin.Id from $pkg/metadata.json" >&2
    exit 1
fi

pot="$dir/template.pot"

# QML is not a language xgettext knows, but every translatable call sits inside
# a JavaScript expression, so the JavaScript backend finds them all. The keyword
# list covers ki18n (i18n*), its disambiguated-domain form (i18nd*), and the
# XML-markup variants.
#
# Paths are relative to the repo root so template.pot does not embed the build
# machine's home directory (which would make every diff machine-specific).
#
# hyprland/ and windows/qml/ are the Quickshell panel and the Windows tray app:
# their shell.i18n(…) calls land in this same catalog (see package/contents/code/I18n.js).
cd "$root"
mapfile -t sources < <(
    find package/contents/ui package/contents/config package/contents/code hyprland windows/qml \
        -type f \( -name '*.qml' -o -name '*.js' \) | LC_ALL=C sort
)
# The KPlugin name and description are read from metadata.json by KJsonUtils,
# which looks up "Name[fr]" / "Description[fr]" in the same domain. They never
# appear in code, so they are declared in this tiny shim.
sources+=("translate/metadata-i18n.js")

xgettext \
    --from-code=UTF-8 \
    --language=JavaScript \
    --qt \
    --add-comments=TRANSLATORS \
    --add-location=file \
    --keyword=i18n --keyword=i18nc:1c,2 --keyword=i18np:1,2 --keyword=i18ncp:1c,2,3 \
    --keyword=i18nd:2 --keyword=i18ndc:2c,3 --keyword=i18ndp:2,3 --keyword=i18ndcp:2c,3,4 \
    --keyword=ki18n --keyword=ki18nc:1c,2 --keyword=ki18np:1,2 --keyword=ki18ncp:1c,2,3 \
    --keyword=xi18n --keyword=xi18nc:1c,2 --keyword=xi18np:1,2 --keyword=xi18ncp:1c,2,3 \
    --package-name="AI Usage Monitor" \
    --package-version="$version" \
    --msgid-bugs-address="$bug_url/issues" \
    --output="$pot" \
    "${sources[@]}"

# xgettext keys the catalog header on the charmap; normalise it so the .pot is
# stable and the merge in a fresh checkout is a no-op.
sed -i 's/^"Content-Type: text\/plain; charset=CHARSET\\n"$/"Content-Type: text\/plain; charset=UTF-8\\n"/' "$pot"

# The creation date changes on every run. Drop it from the .pot and the .po so
# a regenerated catalog is byte-identical to the committed one — the CI sync
# check compares them with `git diff --exit-code`.
sed -i '/^"POT-Creation-Date:/d' "$pot"

shopt -s nullglob
for po in "$dir"/*.po; do
    echo "[i18n] merge $(basename "$po")"
    # File-only locations: line numbers would churn the catalog on every QML
    # edit and trip the CI sync check without a single string changing.
    msgmerge --quiet --update --backup=none --no-fuzzy-matching --add-location=file "$po" "$pot"
    sed -i '/^"POT-Creation-Date:/d' "$po"
    # Drop entries that are no longer in the sources (e.g. brand names unwrapped
    # from i18n()), so the catalog only ever holds live strings.
    msgattrib --no-obsolete --add-location=file "$po" -o "$po"
done
shopt -u nullglob

echo "[i18n] wrote $pot"
