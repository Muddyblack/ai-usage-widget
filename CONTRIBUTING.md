# Contributing

## Dependencies

Installing a release `.plasmoid` (GitHub release or KDE Store) needs only the
runtime [requirements in the README](README.md#requirements): its translations
are already compiled in. Working from a clone of the source is different — the
compiled translations are not in git, and the dev tooling below is on you.

The easy route is `nix develop`, which provides all of it (and installs the git
hooks); `nix develop .#windows` adds PySide6 for the Windows tray app. Without
Nix, install:

| Tool | Needed for |
|---|---|
| Plasma SDK (`kpackagetool6`, `plasmoidviewer`) | `./test_install.sh`, `make view` |
| gettext (`msgfmt`, `xgettext`, `msgmerge`) | compiling translations in `./test_install.sh`, `make view`, `make pack`; `make translations` |
| `zip` | `make pack` |
| Python 3.8+ | the backend and every test suite |
| `jq`, `flock`, `timeout` | `make test` (the shell contract tests) |
| Node.js | `tests/shared-code.test.js` (skipped when `node` is missing) |
| Qt 6 `qmllint`, `qmlformat` | QML lint and formatting |
| `ruff` | `make lint-py` |
| `pre-commit` + Nix | the git hooks — they run `qmlformat`/`qmllint` through `nix develop` |

Only if you work on that part:

- **Windows tray app** — PySide6 and psutil (`windows/requirements.txt`); building
  the `.exe` also needs `windows/build-requirements.txt` (PyInstaller) and Inno
  Setup on Windows. See [`docs/windows.md`](docs/windows.md).
- **Hyprland / Quickshell** — Quickshell, plus CMake and Qt 6 for the tray helper;
  `nix run .#hyprland` brings them. See [`docs/hyprland.md`](docs/hyprland.md).
- **README artwork** — Perl for `readme/generate.pl`; `make opendesktop` needs
  Inkscape.

## Development install

```bash
./test_install.sh
```

Installs as `AI Usage (Test)` alongside the real widget so you can iterate
without touching your live install.

`test_install.sh`, `make view` and `make pack` compile the translations first,
so they need gettext (`msgfmt`); `nix develop` has it. The compiled `.mo`
files under `package/contents/locale/` are git-ignored build output: edit
`translate/*.po` (regenerate with `make translations`), never commit a `.mo`.

## Translations

One catalog per language, `translate/<lang>.po`, serves every frontend. The
Plasma widget loads it compiled (KDE's `i18n()`); the Hyprland panel and the
Windows tray app parse the `.po` itself with `package/contents/code/I18n.js`,
through `shell.i18n()` / `shell.i18nc()` / `shell.i18np()` — the same call shapes,
so `translate/Messages.sh` extracts all three frontends into the same file.
Wrap new UI text in those calls, as one full phrase with `%1` placeholders
rather than pieces joined with `+`.

Adding a language:

```bash
make translations                                   # refresh translate/template.pot
msginit -i translate/template.pot -l de -o translate/de.po
# translate de.po, then:
make translations && make check-translations
```

Nothing else needs registering: the scripts, CI, packaging and all three
frontends pick up every `translate/*.po`. `package/metadata.json` can carry a
`"Name[de]"` / `"Description[de]"` for the widget list.

To remove the test copy:

```bash
kpackagetool6 -t Plasma/Applet -r org.muddyblack.aiUsageWidgetTest
```

Preview the widget without installing it at all:

```bash
make view      # planar
make view-h    # horizontal
```

## Tests

```bash
make test
```

`tests/python/test_fixtures.py` replays the provider envelopes in `tests/fixtures/` through
the in-process normalizers — success, missing credentials, malformed responses,
offline and rate-limited states for every provider. `test_cli.py` renders those
same fixtures through the terminal frontend. No network access is needed, and
the same provider coverage runs on Windows CI.
`test_provider_values.py` pins provider-specific calculations; `test_collect.py`
and `test_muse.py` exercise real file/SQLite readers and response-file hooks.
Recorded API bodies use `*-response.json` in `tests/fixtures/`; tests create
synthetic configs, credentials and session logs in temporary directories.
`tests/shared-code.test.js` covers the JavaScript both QML frontends share.

`tests/python/` holds the portable suites — plain `unittest`, no shell — that
CI also runs on Windows: platform paths, the shared history file and its lock,
the Codex app-server client against a fake `codex.cmd`, finding Antigravity
through `psutil`, credential discovery, and the tray app loading its QML headless
with every settings section opened once (`make test-py`, or
`python windows/app.py --selftest`).

Linting the Python backend and tray app needs `ruff`:

```bash
make lint-py
```

## Adding or changing a provider

The backend owns all provider logic and hands the frontends a versioned JSON
model. Read [`docs/provider-contract.md`](docs/provider-contract.md) first — it
documents the schema, the invariants the contract tests enforce, and the rule
that a statistic must not cost the user money to read.

Per-provider specifics (credential resolution, endpoints, API quirks) are
described in [`docs/providers.md`](docs/providers.md).

## Packaging

```bash
make pack
# compiles the translations, then writes ai-usage-widget-<version>.plasmoid
```

## Releasing

```bash
./tag.sh
```

Prompts for a version bump (patch / minor / major), updates
`package/metadata.json`, commits, tags, and pushes. CI then builds the
`.plasmoid` and creates a GitHub release automatically.
