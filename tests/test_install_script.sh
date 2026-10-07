#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/repo/hosts/kde/contents/ui" "$tmp/repo/assets/icons" "$tmp/repo/scripts"
cp "$repo/test_install.sh" "$tmp/repo/test_install.sh"
cp "$repo/hosts/kde/metadata.json" "$tmp/repo/hosts/kde/metadata.json"
cp "$repo/hosts/kde/contents/ui/main.qml" "$tmp/repo/hosts/kde/contents/ui/main.qml"
cp "$repo/assets/icons/org.muddyblack.aiUsageWidget.svg" "$tmp/repo/assets/icons/"

# A stand-in for the real assembly: just the files test_install.sh renames.
cat > "$tmp/repo/scripts/build-kde-package.sh" <<'FAKE_BUILD'
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$1/contents/ui" "$1/contents/icons"
cp "$root/hosts/kde/metadata.json" "$1/"
cp "$root/hosts/kde/contents/ui/main.qml" "$1/contents/ui/"
cp "$root/assets/icons/org.muddyblack.aiUsageWidget.svg" "$1/contents/icons/"
FAKE_BUILD
chmod +x "$tmp/repo/scripts/build-kde-package.sh"

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
