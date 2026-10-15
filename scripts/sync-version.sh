#!/usr/bin/env bash
# ui/js/ProjectVersion.js is generated from hosts/kde/metadata.json, the one
# place the version is edited (scripts/tag.sh runs this after bumping it).
# `--check` fails instead of writing, for tests and CI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(grep -oE '"Version":[[:space:]]*"[^"]+"' "$ROOT/hosts/kde/metadata.json" | head -1 | sed -E 's/.*"([^"]+)"$/\1/')"
TARGET="$ROOT/ui/js/ProjectVersion.js"
CONTENT="// Generated from hosts/kde/metadata.json by scripts/sync-version.sh; do not edit.
var current = \"${VERSION}\";"

if [[ "${1:-}" == "--check" ]]; then
    [[ -f "$TARGET" && "$(cat "$TARGET")" == "$CONTENT" ]] || { echo "ui/js/ProjectVersion.js is stale: run scripts/sync-version.sh" >&2; exit 1; }
else
    printf '%s\n' "$CONTENT" > "$TARGET"
fi
