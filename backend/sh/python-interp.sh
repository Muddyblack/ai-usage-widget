# python-interp.sh — resolve a Python 3 interpreter into $PY.
#
# Sourced (never executed) by get-ai-usage, export-snapshot and history-io so
# all three agree on which interpreter to use.
#
# Distros disagree on the binary's name: `python3` on anything modern, but bare
# `python` inside virtualenvs/conda and on Arch, and a few minimal images ship
# only a versioned `python3.13`. Resolution order:
#
#   1. $PYTHON3      — explicit override, trusted as-is, never probed
#   2. $PY_DEFAULT   — `python3`, or an absolute store path on Nix (see flake.nix)
#   3. python3, python, python3.13 … python3.8
#
# Names that encode the major version are accepted on a PATH lookup alone. Bare
# `python` is executed once to confirm it is not Python 2, which still lingers
# as /usr/bin/python on old installs — a wrong guess there would fail with a
# SyntaxError instead of the readable "missing" state the frontends render.
#
# Callers must treat an empty $PY as "no interpreter available".

PY_DEFAULT="python3"

# Cheap check: name implies Python 3, so existence on PATH is enough.
_py_versioned_ok() {
    command -v "$1" >/dev/null 2>&1
}

# Costs one process spawn — only used for ambiguous names.
_py_probe_ok() {
    command -v "$1" >/dev/null 2>&1 &&
        "$1" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 8) else 1)' \
            >/dev/null 2>&1
}

# Sets $PY to the first usable interpreter. Returns 1 (and leaves $PY empty)
# when there is none.
py_resolve() {
    PY=""

    if [ -n "${PYTHON3:-}" ]; then
        if command -v "$PYTHON3" >/dev/null 2>&1; then
            PY="$PYTHON3"
            return 0
        fi
        # An override that does not exist is a user error worth surfacing
        # rather than silently papering over with a different interpreter.
        return 1
    fi

    if _py_versioned_ok "$PY_DEFAULT"; then
        PY="$PY_DEFAULT"
        return 0
    fi

    for _py_candidate in python3 python3.13 python3.12 python3.11 python3.10 python3.9 python3.8; do
        if _py_versioned_ok "$_py_candidate"; then
            PY="$_py_candidate"
            return 0
        fi
    done

    if _py_probe_ok python; then
        PY="python"
        return 0
    fi

    return 1
}
