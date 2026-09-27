#!/usr/bin/env bash
# The translation build is incremental, and the shell launcher's provider list
# has not drifted from the canonical Python list.
#
# The two checks are deliberately separate: the build check proves an
# unchanged .po skips compilation (the reason `make view`/`pack` got slower
# with every run), while the parity check turns a hand-maintained duplicate
# into a failing test instead of a silent drift.

export LC_ALL=C.UTF-8
export LANGUAGE=
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
sh_dir="$repo/package/contents/tools/sh"

# ── provider list parity ──────────────────────────────────────────────
# The shell list must equal config.ALL_PROVIDERS exactly (order included),
# because --list and the missing-python3 fallback enumerate providers without
# importing Python.
canonical="$(PYTHONPATH="$repo/package/contents/tools" python3 -c \
    'from aiusage import config; print(" ".join(config.ALL_PROVIDERS))')"
shell_list="$("$sh_dir/get-ai-usage" --list | tr '\n' ' ' | sed 's/ $//')"
if [ "$canonical" != "$shell_list" ]; then
    printf 'translation-provider-parity: shell list drifted\n  canonical: %s\n  shell:     %s\n' \
        "$canonical" "$shell_list" >&2
    exit 1
fi

# ── incremental translation build ─────────────────────────────────────
if ! command -v msgfmt >/dev/null 2>&1; then
    printf 'translation-provider-parity: msgfmt missing (gettext); build check skipped\n' >&2
else
    # Build in a throwaway copy: the check deletes and touches files, which
    # must never happen to the working tree.
    tmp="$(mktemp -d)"
    trap 'rm -rf -- "$tmp"' EXIT
    mkdir -p "$tmp/translate" "$tmp/package"
    cp "$repo/translate/build.sh" "$repo/translate/fr.po" "$tmp/translate/"
    cp "$repo/package/metadata.json" "$tmp/package/"
    build="$tmp/translate/build.sh"
    mo="$tmp/package/contents/locale/fr/LC_MESSAGES/plasma_applet_org.muddyblack.aiUsageWidget.mo"
    mtime() { python3 -c 'import os, sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "$1"; }

    # A clean build compiles.
    "$build" >/dev/null
    [ -e "$mo" ] || { printf 'translation-provider-parity: clean build produced no .mo\n' >&2; exit 1; }

    # A repeated build with an unchanged .po skips (no output, mtime held).
    before="$(mtime "$mo")"
    out="$("$build")"
    after="$(mtime "$mo")"
    if [ -n "$out" ]; then
        printf 'translation-provider-parity: unchanged build recompiled: %s\n' "$out" >&2
        exit 1
    fi
    if [ "$before" != "$after" ]; then
        printf 'translation-provider-parity: unchanged build rewrote the .mo\n' >&2
        exit 1
    fi

    # A forced build compiles regardless.
    out="$(FORCE_TRANSLATIONS=1 "$build")"
    case "$out" in
        *"[i18n] fr"*) ;;
        *) printf 'translation-provider-parity: forced build did not recompile: %s\n' "$out" >&2; exit 1 ;;
    esac

    # A newer .po triggers exactly its own rebuild.
    sleep 1
    touch "$tmp/translate/fr.po"
    out="$("$build")"
    case "$out" in
        *"[i18n] fr"*) ;;
        *) printf 'translation-provider-parity: newer .po did not rebuild: %s\n' "$out" >&2; exit 1 ;;
    esac
fi

echo "translation-provider-parity: all assertions passed"
