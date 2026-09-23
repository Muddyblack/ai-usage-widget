# The Windows tray app

A tray app with the same popup as the Hyprland panel — the QML is shared, not
copied — backed by the same provider package. Preview quality.

## Installing it

Download `AI-Usage-Setup-<version>.exe` from a release and run it: no admin
rights, a Start menu entry, an optional *Start when I sign in*, and an
uninstaller under *Installed apps*; running a newer one updates in place. (Or
take `ai-usage-windows-<version>.zip`, unzip it anywhere and run
`AI Usage.exe`.) The app isn't code-signed yet, so SmartScreen asks once:
*More info → Run anyway*. Nothing else to install — Python and Qt ship inside
the folder.

## Package managers

Stable releases built with package-manager support attach `ai-usage.json`
(Scoop) and `ai-usage-winget-<version>.zip` (WinGet manifests) alongside the
Windows binaries. Wait for the Windows assets to appear before installing.
Both target x64 Windows and keep settings/history in the locations below.

### Scoop

With [Scoop](https://scoop.sh/) installed, run in PowerShell:

```powershell
scoop install https://github.com/Muddyblack/ai-usage-widget/releases/latest/download/ai-usage.json
```

Launch **AI Usage** from the Start menu. Quit the tray app before updating:

```powershell
scoop update ai-usage
```

Scoop remembers the manifest URL, so installing from the `latest/download`
URL follows subsequent releases. Installing a version-specific manifest pins
that source to that release. The manifest also includes `checkver` and
`autoupdate` for maintainers who want to add it to a Scoop bucket; this
repository does not currently publish a bucket.

Before `scoop uninstall ai-usage`, switch off **Start with Windows** in the
app and quit it. Settings and history survive uninstall. Use one installation
method at a time: uninstall an existing Inno/WinGet copy before moving to Scoop
to avoid duplicate shortcuts and competing autostart entries.

### WinGet

The release ZIP contains the three manifests under
`manifests/m/Muddyblack/AIUsage/<version>/`, ready for validation and submission
to [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs).
Generating these files does **not** register the app in the public catalog.

To test a release before catalog acceptance, download and extract its
`ai-usage-winget-<version>.zip`. Enable local manifests once from an elevated
terminal (`winget settings --enable LocalManifestFiles`), then run from a
normal PowerShell terminal, replacing `<version>`:

```powershell
winget validate --manifest .\manifests\m\Muddyblack\AIUsage\<version>
winget install --manifest .\manifests\m\Muddyblack\AIUsage\<version>
```

The manifest uses the existing per-user Inno installer, including its stable
uninstall identity and in-place updates. Installation leaves autostart off by
default; enable it in the app. Existing autostart preferences survive upgrades.
After a maintainer submits the manifests and the public catalog accepts them,
users can install and update with:

```powershell
winget install --id Muddyblack.AIUsage --exact --source winget
winget upgrade --id Muddyblack.AIUsage --exact --source winget
```

### Maintaining the manifests

The Windows build runs `windows/package-manifests.py` after packaging each
stable release. It hashes the actual ZIP and installer, checks the portable
archive layout, and writes version-specific download URLs. To reproduce:

```powershell
python windows/package-manifests.py --version 3.2.0 --assets . --output dist/package-manifests
```

Use assets from that exact release; rebuilding a binary changes its hash.
For each WinGet release, validate and test the extracted manifests on Windows,
then submit the version folder following Microsoft's
[submission instructions](https://learn.microsoft.com/en-us/windows/package-manager/package/repository).
Catalog submissions are separate from the release workflow.

### Microsoft Store

Store distribution is a follow-up; there is no Store package or listing in
this change. The existing installer already supports silent, offline installs,
but the EXE submission route requires trusted code signing for the installer
and all bundled PE binaries, plus versioned URLs submitted through Partner
Center. The current build is unsigned. See Microsoft's
[EXE/MSI requirements](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msi/app-package-requirements).

Alternatively, MSIX offers Store-managed signing and updates, but needs its
own packaging and Windows testing, particularly for tray startup, autostart,
and access to the CLI credentials under the user's profile. Choose that route
as a separate packaging task once the Store publisher identity is available.

## Using it

It sits in the notification area: click the icon for the popup, right-click for
**Refresh**, **Settings**, **Tray style**, **Floating pill**, **Start with
Windows** and **Quit**. Three tray styles (also under *Settings → Display*):

- **Ring** (default) — a single icon, the logo inside a usage ring: one icon to
  keep in view.
- **Logo and percent** — like the panel pill: for each value of the active tab,
  the provider's logo tinted by level, then `NN%`. Windows gives every tray icon
  the same square, so that is two icons per value.
- **Numbers** — the logo once, then each value as plain coloured digits.

**Floating pill** adds the panel's own pill as a small always-on-top window —
drag it anywhere, it stays where it was left; a click opens the popup beside it.

Windows 11 puts new tray icons in the `^` overflow at first — which is why the
very first start opens the popup by itself: drag the icon onto the taskbar
once, or turn it on under *Settings → Personalization → Taskbar → Other system
tray icons*. Starting AI Usage again from the Start menu while it runs opens
the popup too.

*Settings → Display → Language* picks the language, and switches it on the spot.
Its default follows the display language — `$LANGUAGE` when set, otherwise the
system's — when there is a translation for it (French so far), and English
otherwise. The list is every `translate/*.po` bundled with the app: the Plasma
widget's own catalogs.
Provider rows the backend words itself (limits, token counts) are still English.

## Where it keeps its files

It reads the same logins as on Linux, which the CLIs keep under your profile on
Windows too (`%USERPROFILE%\.claude`, `.codex`, `.gemini`, `.copilot`, …). The
VS Code-family IDEs (Cursor, Kiro) are read from `%APPDATA%`. Its own files:

| What | Where |
|---|---|
| Settings (same format as Hyprland's) | `%APPDATA%\ai-usage-widget\hyprland-settings.json` |
| Usage history | `%LOCALAPPDATA%\ai-usage-widget\` |
| Log (Qt warnings and Python errors; the previous one is `tray.log.1`) | `%LOCALAPPDATA%\ai-usage-widget\tray.log` |

Antigravity is found through `psutil`, which the build bundles.

### Provider defaults and detection

Windows uses the shared backend and the shared JSON settings file at
`%APPDATA%\ai-usage-widget\hyprland-settings.json`. New settings are zero
based. The explicit `--initialize-provider-defaults` operation may enable only
providers with approved local evidence, then sets `providerDefaultsApplied` so
the operation does not repeat. Refresh and `--all` never initialize settings.
The Windows app must not be described as using Plasma's KConfig defaults.

Detection is stat-only and reports local evidence, not authentication or
usability. It does not read credential contents, use the network, open SQLite,
run a command, or return secrets. See
[`provider-detection.md`](provider-detection.md) for the current allowlist and
the shared provider-addition checklist.

## How it fits together

`windows/` is a PySide6 host for the same popup the Hyprland panel draws. It
adds no provider logic of its own:

| Part | Lives in | Shared with |
|---|---|---|
| Provider data, credentials, maths | `package/contents/tools/aiusage` | every frontend |
| Usage history file and its lock | `aiusage/historyio.py` | Plasma + Hyprland, via `tools/sh/history-io` |
| Platform directories | `aiusage/paths.py` | every frontend |
| Popup layout | `hyprland/PopupContent.qml` | Hyprland |
| Settings page, rows, chart, stats | `hyprland/*.qml` | Hyprland |
| Provider display registry | `hyprland/ProviderRegistry.js` | Hyprland |
| Countdown / history JS | `package/contents/code/*.js` | Plasma + Hyprland |
| Window, tray icon, autostart | `windows/app.py`, `windows/qml/Main.qml` | — |

`Main.qml` and `hyprland/AiUsageShell.qml` are the two implementations of the
`shell` interface that `PopupContent.qml` and `SettingsPage.qml` read. A
property added to one belongs in the other.

## Running it

On Linux, which is how it is developed:

```bash
make run-windows              # PySide6 + psutil from `nix develop .#windows`
python windows/app.py         # the same, from inside `nix develop .#windows`
python3 windows/app.py        # or any Python with windows/requirements.txt installed
```

On Windows, from a checkout:

```powershell
pip install -r windows/requirements.txt
python windows\app.py
```

Starting it a second time toggles the running instance's popup instead of
opening another tray icon.

## Checking it without a desktop

```bash
python3 windows/app.py --selftest                      # exit 1 on any QML warning
python3 windows/app.py --screenshot popup.png          # after the first refresh
python3 windows/app.py --screenshot settings.png --settings
```

`--selftest` opens every settings section once, so a binding that only breaks on
a hidden page still fails it. `tests/python/test_windows_app.py` runs it with
every provider switched off, so it needs no network.

## Building the .exe

On Windows (PyInstaller does not cross-compile):

```powershell
pip install -r windows/build-requirements.txt
pyinstaller --noconfirm windows/ai-usage.spec
"dist\AI Usage\AI Usage.exe" --selftest
```

`windows/build-requirements.txt` pins the exact PySide6, PyInstaller and Pillow
the releases are built with, so a tag rebuilt later gives the same `.exe`.
`windows/requirements.txt` keeps the ranges the app itself needs; CI's test job
installs those as they come, so a new PySide6 is tried there before a bump of
the pins ships it.

The result is a folder, `dist\AI Usage\`, rather than a single file: a one-file
build unpacks itself to a temp directory on every start. Zip the folder to ship
it.

The installer wraps that folder (Inno Setup, `windows/installer.iss`):

```powershell
windows\build-installer.ps1 -Version 2.4.0     # → AI-Usage-Setup-2.4.0.exe
```

It installs per user (no admin rights) to `%LOCALAPPDATA%\Programs\AI Usage`,
adds a Start menu entry, optionally a desktop shortcut and *Start when I sign
in* (the same registry value as the tray menu's switch), stops a running copy
before replacing it, and registers an uninstaller. Keep its `AppId` as it is:
that is how a newer installer finds and updates the installed app. An update
does not offer *Start when I sign in* again — it leaves the setting as the app
last had it — and a silent update (`/SILENT`, winget) starts the app again if
it was running.

CI does all of this on every push and pull request
(`.github/workflows/windows.yml`, kept as a workflow artifact for two weeks),
and on demand from any branch (*Actions → Windows → Run workflow*). A tag runs
the same workflow from `release.yml`, which attaches the installer and the zip
to the release once they have passed — after the `.plasmoid`, which a failing
Windows build does not hold back.

## Testing on real Windows

Docker and distrobox cannot run this: Windows containers need a Windows host,
and distrobox runs Linux only. Wine runs the backend but is not worth trusting
for the tray or window behaviour. What works:

- **A KVM virtual machine** — the main loop for anything visual.
  - `quickemu` (in nixpkgs): `quickget windows 11`, then `quickemu --vm windows-11.conf`.
  - [`dockur/windows`](https://github.com/dockur/windows) — the "docker" way: a
    KVM Windows VM inside a container, with a web viewer and RDP. Easy to throw
    away and recreate from a compose file.
  - virt-manager with libvirt, if it is already set up.

  Share the checkout into the VM (virtiofs, or an SMB share) so you edit on
  Linux and only run on Windows.
- **CI** — every push runs `tests/python` and `--selftest` on `windows-latest`,
  and builds the `.exe`, which then has to pass `--selftest` itself. That
  catches most regressions without starting a VM.

Worth checking by hand in a VM, since no test covers it:

- the popup opens against the taskbar next to the icon, with the taskbar on each
  edge;
- the first start after installing opens the popup by itself, and only that
  once; starting the app again from the Start menu opens it *with focus*, so a
  click elsewhere closes it;
- an update keeps *Start with Windows* as it was, and a `/SILENT` update of a
  running app starts it again;
- each tray style (Ring — the default here — Logo and percent, Numbers) reads at 100 %, 125 % and
  150 % display scaling, on a light and a dark taskbar, and the icons keep their
  places (and "show in taskbar" choice) across a restart;
- each logo sits to the left of its number: the icons are created newest-last
  on the assumption that Windows, like Plasma, lays them out newest-first
  (`TrayApp._show_entries`) — flip that if Windows turns out not to;
- a number below 70 % is white on a dark taskbar and near-black on a light one
  (read from the "system" light/dark setting);
- the floating pill: its slot logos show (they are tinted by a GPU effect, so
  check a machine without GPU acceleration too — a VM, a remote desktop), a
  drag moves it and a click opens the popup beside it, and it comes back where
  it was left after a restart, or above the taskbar when that screen is gone;
- a click on the icon while the popup is open closes it rather than reopening it;
- **Start with Windows** survives a sign-out;
- no console window flashes up on a refresh (Codex and `gh` are console programs);
- each provider you use finds its login — the paths below are the ones not yet
  confirmed on a real machine.

## Where things are on Windows

Confirmed by construction (the CLIs use `%USERPROFILE%\.<name>` on Windows too,
which is what `~/.<name>` resolves to): Claude, Codex, Gemini/Antigravity
accounts, Grok, Cline, Kimi, the Copilot CLI.

Still to confirm on a real install:

| Provider | Looked for at |
|---|---|
| Cursor IDE | `%APPDATA%\Cursor\User\globalStorage\state.vscdb` |
| Kiro IDE | `%APPDATA%\Kiro\User\globalStorage\state.vscdb` |
| cursor-agent | `%APPDATA%\cursor\auth.json` |
| kiro-cli | `%LOCALAPPDATA%\kiro-cli\data.sqlite3` |
| Muse | `%LOCALAPPDATA%\muse\…`, `%APPDATA%\muse\…` |
| Copilot editor plugins | `%LOCALAPPDATA%\github-copilot\apps.json` |
| Z.AI via glm-acp-agent | `%USERPROFILE%\.config\glm-acp-agent\credentials.json` (the Linux path under the profile; the tool may use `%APPDATA%` instead) |

Everything else is either one of those dotfile folders or a key file of the
widget's own (`~/.config/deepseek/api-key` and the like), which no vendor tool
writes: on Windows it is simply looked for under `%USERPROFILE%\.config\`, and
the Settings page or an environment variable is the usual way in anyway.

Every one of them can be pointed elsewhere with the provider's environment
variable (`CURSOR_IDE_DB`, `KIRO_IDE_DB`, `KIRO_CLI_DB`, `MUSE_SESSIONS_DIR`, …)
while a path is being confirmed.
