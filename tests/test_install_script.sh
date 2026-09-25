#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/repo/package/contents/ui" "$tmp/repo/package/contents/icons" "$tmp/repo/translate"
cp "$repo/test_install.sh" "$tmp/repo/test_install.sh"
cp "$repo/package/metadata.json" "$tmp/repo/package/metadata.json"
cp "$repo/package/contents/ui/main.qml" "$tmp/repo/package/contents/ui/main.qml"
cp "$repo/package/contents/icons/org.muddyblack.aiUsageWidget.svg" "$tmp/repo/package/contents/icons/"

cat > "$tmp/repo/translate/build.sh" <<'FAKE_BUILD'
#!/usr/bin/env bash
exit 0
FAKE_BUILD
chmod +x "$tmp/repo/translate/build.sh"

cat > "$tmp/bin/kpackagetool6" <<'FAKE_TOOL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_KPACKAGE_LOG"
case " $* " in
    *" -l "*) if [ -f "$FAKE_INSTALLED" ]; then printf '%s\n' 'org.muddyblack.aiUsageWidgetTest'; fi ;;
    *" -i "*) touch "$FAKE_INSTALLED" ;;
esac
FAKE_TOOL
chmod +x "$tmp/bin/kpackagetool6"

root="$tmp/home/.local/share/plasma/plasmoids"
export FAKE_KPACKAGE_LOG="$tmp/kpackage.log" FAKE_INSTALLED="$tmp/installed"
export HOME="$tmp/home" XDG_DATA_HOME="$tmp/home/.local/share" TMPDIR="$tmp" PATH="$tmp/bin:$PATH"

"$tmp/repo/test_install.sh" >/dev/null
grep -F -- "-p $root -l" "$FAKE_KPACKAGE_LOG" >/dev/null
grep -F -- "-p $root -i " "$FAKE_KPACKAGE_LOG" >/dev/null
if grep -F -- "-p $root -u " "$FAKE_KPACKAGE_LOG" >/dev/null; then
    echo "test_install: attempted upgrade on a fresh install" >&2
    exit 1
fi

: > "$FAKE_KPACKAGE_LOG"
"$tmp/repo/test_install.sh" >/dev/null
grep -F -- "-p $root -l" "$FAKE_KPACKAGE_LOG" >/dev/null
grep -F -- "-p $root -u " "$FAKE_KPACKAGE_LOG" >/dev/null
if grep -F -- "-p $root -i " "$FAKE_KPACKAGE_LOG" >/dev/null; then
    echo "test_install: attempted fresh install for an existing widget" >&2
    exit 1
fi

echo "test_install: ok"
