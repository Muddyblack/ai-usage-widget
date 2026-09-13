#!/usr/bin/env bash
# The backend is gettext-translated; pin the locale so English assertions hold.
export LC_ALL=C.UTF-8
export LANGUAGE=
set -euo pipefail

# tools/sh/python-interp.sh resolves the interpreter every shell tool runs on.
# Getting it wrong is not a soft failure: the widget renders "python3 missing"
# for every provider (which is what NixOS saw, since plasmashell's PATH has no
# Python at all), or worse, picks a Python 2 and dies on a SyntaxError.
#
# Each case builds a PATH containing exactly one shape of Python and asserts
# which binary py_resolve settles on.

repo="$(cd "$(dirname "$0")/.." && pwd)"
sh_dir="$repo/package/contents/tools/sh"
real_py="$(command -v python3)"
bash_bin="$(command -v bash)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A PATH with the coreutils the helper needs, but no Python under any name.
base="$tmp/base"
mkdir -p "$base"
for b in basename dirname env bash date tr; do ln -sf "$(command -v "$b")" "$base/$b"; done

# Runs py_resolve in a pristine environment and prints the basename of $PY
# ("" when nothing resolved).
resolve() { # <path> [PYTHON3 override]
    env -i HOME="$HOME" PATH="$1" ${2:+PYTHON3="$2"} "$bash_bin" --noprofile --norc -c \
        '. "$0"/python-interp.sh; py_resolve || true; printf "%s" "$(basename "${PY:-}")"' \
        "$sh_dir"
}

assert_resolves() { # <label> <expected> <actual>
    if [ "$2" != "$3" ]; then
        printf 'python-interp: %s — expected %s, got %s\n' \
            "$1" "${2:-<none>}" "${3:-<none>}" >&2
        exit 1
    fi
}

# Nothing to find -> empty $PY, and the caller renders the missing state.
assert_resolves "no interpreter" "" "$(resolve "$base")"

d="$tmp/p3"; mkdir -p "$d"; ln -sf "$real_py" "$d/python3"
assert_resolves "python3" "python3" "$(resolve "$base:$d")"

# Arch and every activated virtualenv/conda env expose only a bare `python`.
d="$tmp/bare"; mkdir -p "$d"; ln -sf "$real_py" "$d/python"
assert_resolves "bare python" "python" "$(resolve "$base:$d")"

# Some minimal images ship only the versioned binary.
d="$tmp/ver"; mkdir -p "$d"; ln -sf "$real_py" "$d/python3.13"
assert_resolves "versioned" "python3.13" "$(resolve "$base:$d")"

# A `python` that is not Python 3 must be rejected rather than handed the
# backend, which would fail with a traceback instead of a readable error.
d="$tmp/py2"; mkdir -p "$d"
cat >"$d/python" <<'EOF'
#!/bin/sh
# stands in for /usr/bin/python on an install that still has Python 2
exit 1
EOF
chmod +x "$d/python"
assert_resolves "python2 rejected" "" "$(resolve "$base:$d")"

# ...but a usable python3 alongside it still wins.
ln -sf "$real_py" "$d/python3"
assert_resolves "python3 preferred over python2" "python3" "$(resolve "$base:$d")"

# $PYTHON3 outranks everything on PATH.
assert_resolves "PYTHON3 override" "python3.13" \
    "$(resolve "$base:$tmp/ver" "$tmp/ver/python3.13")"

# A broken override is surfaced, not silently replaced with another interpreter:
# a user who set $PYTHON3 wants that one or an error.
assert_resolves "broken PYTHON3 override" "" "$(resolve "$base:$d" /nonexistent/python)"

# The Nix build rewrites PY_DEFAULT to an absolute store path (see flake.nix),
# so an absolute default has to resolve as-is, without a PATH lookup.
printf '%s' "$(sed "s|^PY_DEFAULT=\"python3\"|PY_DEFAULT=\"$real_py\"|" \
    "$sh_dir/python-interp.sh")" >"$tmp/pinned.sh"
pinned="$(env -i HOME="$HOME" PATH="$base" "$bash_bin" --noprofile --norc -c \
    '. "$0"; py_resolve || true; printf "%s" "${PY:-}"' "$tmp/pinned.sh")"
assert_resolves "pinned absolute default" "$real_py" "$pinned"

# get-ai-usage must keep answering --list without any interpreter, since the
# frontends call it to enumerate providers before they can report an error.
list="$(env -i HOME="$HOME" PATH="$base" "$sh_dir/get-ai-usage" --list | tr '\n' ' ')"
case "$list" in
    *claude*openai*) ;;
    *) printf 'python-interp: --list broken without an interpreter: %s\n' "$list" >&2; exit 1 ;;
esac

# With no interpreter the launcher still emits a contract-shaped envelope
# carrying the fixed "python3 missing" vocabulary (docs/provider-contract.md).
envelope="$(env -i HOME="$HOME" PATH="$base" "$sh_dir/get-ai-usage" --provider claude)"
case "$envelope" in
    *'"schemaVersion":1'*'"error":"python3 missing"'*) ;;
    *) printf 'python-interp: missing-interpreter envelope malformed: %s\n' "$envelope" >&2; exit 1 ;;
esac

echo "python-interp: all assertions passed"
