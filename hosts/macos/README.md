# The macOS host

The macOS app is the shared tray app (`hosts/desktop/app.py`) showing the one
shared UI (`ui/`), with a native menu bar item instead of Qt's tray icon. This
directory holds only what is macOS's own:

```
statusitem.py        NSStatusItem through PyObjC: the values as menu bar text,
                     the provider logo as a template image, click / right-click
vibrancy.py          the system blur (NSVisualEffectView) behind the popup
loginitem.py         start at login as an SMAppService login item (the bundled app)
ai-usage.spec        PyInstaller spec -> dist/AI Usage.app (LSUIElement, no Dock icon)
build-app.sh         Finder icon + PyInstaller
package-dmg.sh       dist/AI Usage.app -> ai-usage-macos-<version>-<apple-silicon|intel>.dmg
notarize.sh          Developer ID signing + notarization (releases, with Apple secrets)
entitlements.plist   the hardened-runtime exceptions notarize.sh signs with
requirements.txt     runtime: the desktop app's needs + PyObjC (Cocoa, ServiceManagement)
build-requirements.txt  pinned versions for release builds
```

`docs/macos.md` has the paths, the Python notes and the distribution notes.

## Running it from a checkout

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r hosts/macos/requirements.txt
python hosts/desktop/app.py
```

Without PyObjC the app still runs, with Qt's plain tray icon in the menu bar.

## Building the app

```bash
pip install -r hosts/macos/build-requirements.txt
hosts/macos/build-app.sh            # dist/AI Usage.app
hosts/macos/package-dmg.sh          # ai-usage-macos-<version>-<apple-silicon|intel>.dmg
```
