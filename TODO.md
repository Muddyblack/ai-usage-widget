# TODO

Working notes for the feature-tabs + sessions work. Nothing here is committed yet;
`git status` is the source of truth for the diff.

## Done

### Backend — local sessions (`package/contents/tools/aiusage/sessions.py`)
- [x] `--sessions`: merged, newest-first, redacted list (title / session name / state /
      `lastActivityAt` / detail) from Cline, Muse, Codex, Grok and Claude stores.
      Paths and transcripts never leave this module.
- [x] `--open-session <key>`: resumes one listed session in the user's own terminal.
- [x] `_open_key()` — opaque `sha1(provider:id)[:16]` handle, content-addressed so a
      concurrent refresh can only shift a key onto the same session or fail closed.
- [x] `_RESUME_SPECS` — claude `--resume <id>`, codex `resume <id>`, grok `--resume <id>`,
      cline `--id <id>`; Muse is display-only (`openKey: ""`) because it ships no usable
      binary and documents no resume flag.
- [x] `_terminal_launch()` — `$TERMINAL` first (through `sh` so its flags survive), then
      ghostty / alacritty / kitty / wezterm / konsole / gnome-terminal / xfce4-terminal /
      xterm; detached, `start_new_session=True`, cwd from the session when it still exists;
      if no terminal is installed the session resumes in the background instead of the
      button doing nothing; the window is held open (`exec $SHELL`) so a TUI that exits
      immediately stays readable.
- [x] `__main__.py` — flag parsing, `USAGE` help, exit code 1 + JSON `{ok,message}` on
      failure. Messages name binaries and terminals only, never paths.
- [x] `--help`, `--sessions` and `--all` run clean against the live home dir
      (60 sessions, 9 providers).

### Feature tabs (Overview / Usage & Spend / Sessions)
- [x] `package/contents/code/FeatureTabs.js` — one shared definition of the three optional
      tabs: `enabled` / `defaultEnabled` (Overview on, Spend on, Sessions off) / `label` /
      `accent` / `spendProviderRows` / `spendTotal`.
- [x] KDE widget — `config/main.xml` keys (`overviewEnabled`, `spendEnabled`,
      `sessionsEnabled`), `SettingsPanel.qml` Views section, `main.qml`
      (`enabledTabs` / `panelTab` / `selectTab` / `tabColor` / `tabIcon`, popup wiring) and
      `OverviewTab.qml`, `SpendTab.qml`, `SessionsTab.qml`.
- [x] Hyprland — `AiUsageShell.qml` (`popupTabs`, `activeIsFeature`, `providerById`,
      `refreshSessions`, fallback to the first enabled feature), `PopupContent.qml`,
      `SettingsPage.qml`, `OverviewPage.qml`, `SpendPage.qml`, `SessionsPage.qml`.
- [x] Windows — `app.py` (`collect_sessions_json` / `refreshSessions` / `sessionsReady`)
      and `Main.qml`; shares the Hyprland `PopupContent.qml` + `SettingsPage.qml`, so the
      same Views toggles drive it.
- [x] macOS — `SettingsStore.featureEnabled/setFeature` (same keys, same shared settings
      file), `SettingsView` Views tab, `AppModel.featureTabs/spendRows/showFeature/
      refreshSessions/localSessions`, `Backend.sessions()`, `FeatureView` / `SpendRow` /
      `CostDetails` / `AnyJSON` in `Contract.swift`, plus `OverviewView.swift`,
      `SpendView.swift`, `SessionsView.swift`.

### Fixes along the way
- [x] KDE Views toggles respected their defaults when the config key was unset (was
      `=== true`, so a fresh install read everything as off).
- [x] `SpendTab` / `FeatureTabs.js` fall back to `stats.totalCostUSD` and the missing
      `codexStatsTotalCostUSD` plumbing was added — live `--all` shows cursor org cost 0
      while stats cost is non-zero.
- [x] macOS i18n tests: the Views `ForEach` was unrolled to literals and `%1%` became
      `%1` so `xgettext` can extract them.

### Verification
- [x] `pytest tests/python/` → `157 passed, 23 skipped, 603 subtests passed`.
- [x] `node --check package/contents/code/FeatureTabs.js`.
- [x] `python3 -m py_compile` on the backend modules.
- [x] Swift cannot be built on Linux; the Python mirrors (`test_macos_contract.py`,
      `test_macos_i18n.py`, launcher test) are the stand-in and they pass.

### Resume button in the four frontends — done
- [x] KDE `package/contents/ui/SessionsTab.qml` — per-row ⧉ `ToolButton` carrying
      `openKey`, a `Plasma5Support.DataSource` call to `./get-ai-usage --open-session
      <key>`, and a status line (`notice`) for the returned message. The row's
      provider-select `MouseArea` was pushed to `z: -1` so the button gets the click.
- [x] Hyprland `hyprland/AiUsageShell.qml` — `openSession(key)` + `Process`
      (`openSessionProcess`) + `sessionsNotice`; `hyprland/SessionsPage.qml` gets a ⧉
      button (matching the refresh button's Rectangle/MouseArea style) and the notice.
- [x] Windows — `windows/app.py` `openSession` slot on the worker pool +
      `openSessionFinished` signal (`open_session_json()` wraps `sessions.open_session`);
      `windows/qml/Main.qml` `root.openSession()` + `onOpenSessionFinished` handler +
      `sessionsNotice`. `SessionsPage.qml` is shared with Hyprland, so the button rode
      along unchanged.
- [x] macOS `SessionsView.swift` — ⧉ button per row → `AppModel.openSession(key)` →
      `Backend.openSession(key)`. The row is no longer a `Button` (SwiftUI does not
      route taps to a `Button` nested in another `Button`'s label); `.onTapGesture` on
      the row does the provider-select instead, so the resume button stays tappable.
- [x] Rows with `openKey === ""` (Muse) render no button on any frontend.

### macOS compile break — fixed
- [x] `Contract.swift` gained `LocalSessions` / `LocalSession` (lenient `Decodable`,
      same per-field pattern as `Envelope`): `updatedAt`, `sessions[]` → `provider`,
      `title`, `sessionName`, `state`, `lastActivityAt`, `detail`, `openKey`, plus
      `isActive`.
- [x] `BackendRunner.swift` — `Backend.openSession(key)` bypasses `run()`'s nonzero-exit
      guard (`collect(..., ignoreStatus: true)`), since `--open-session` exits 1 on a
      failure that still has a JSON `{ok,message}` to show, not throw. Added
      `OpenSessionResult: Decodable`.

### Tests — done
- [x] `tests/python/test_sessions_open.py` — `open_session()` malformed/stale keys fail
      closed with "refresh" in the message; the failure message never contains the real
      session id or cwd; a key resolves and spawns a fake `$TERMINAL` (stubbed via
      `shutil.which` / `subprocess.Popen`, no real terminal) with the right argv/cwd;
      missing resume binary and no-resume-command-for-provider (Muse) fail closed;
      `_open_key()` stability and collision checks.
- [x] `pytest tests/python/` → 167 passed, 23 skipped, 609 subtests. `ruff check` clean
      on the new test file.

### Docs — done
- [x] `README.md` — new Features bullet for the three optional tabs, the resume button,
      and the `--sessions` / `--open-session` flags.
- [x] `docs/providers.md` — new "Local sessions" section: what's redacted, which
      providers resume (`claude --resume` / `codex resume` / `grok --resume` /
      `cline --id`), and that Muse cannot.

### Sessions tab polish (follow-up round) — done
- [x] Default Views toggles flipped: Sessions on by default, Overview and Spend off
      (`FeatureTabs.js` `defaultEnabled()`, `config/main.xml`, Hyprland/Windows
      settings-object defaults + load-time coercion, macOS `SettingsStore.featureEnabled`).
- [x] Resume button icon changed from the generic ⧉/play glyph to a terminal icon on
      every frontend: `utilities-terminal` (KDE `icon.name`), `❯_` monospace glyph
      (Hyprland/Windows, shared `SessionsPage.qml`), SF Symbol `terminal` (macOS).
- [x] Search bar added to the Sessions tab on all four frontends — client-side text
      filter over title/sessionName/detail/provider, no backend round-trip:
      `filterText` + `filteredSessions` in `SessionsTab.qml`, `SessionsPage.qml`
      (shared Hyprland/Windows) and `SessionsView.swift` (macOS, `@State` + computed
      property), each with its own "no sessions match your search" empty state.
- [x] Per-session token/price detail on expand — scoped out for this round per
      discussion: Cline and Grok already surface tokens (and cost, when nonzero) in
      the `detail` field; Claude, Codex and Muse don't compute it yet and would need
      new backend parsing. Revisit as its own task if wanted.
- [x] `pytest tests/python/` still green (167 passed, 23 skipped) after the default
      flip — no test asserted the old Overview/Spend-on defaults.

### Round 3: titles, tokens, sticky list, pill fallback, CI screenshots — done
- [x] Claude Code session titles now show the session's own opening prompt (from
      `~/.claude/history.jsonl`'s `display` field, first entry per `sessionId`),
      clipped to 60 chars via `_clip_title()`, with the untruncated text as
      `fullTitle`. Folder name moved to `detail`. **Investigated and reverted** the
      same idea for Cline: its `prompt` field looked like an opening message but is
      actually a rolling snapshot of recent tool output/grep results/other-project
      paths — confirmed against real local data (`/mnt/projects/work/merge.py`
      bled into a widget-project session). `providers/cline.py` documents why it
      stays untouched; `test_sessions_titles.py` has a regression guard.
- [x] Per-session token totals: Codex reads its own last `token_count` event's
      `total_token_usage.total_tokens` (cumulative, no message content read);
      Claude Code sums `usage.{input,output,cache_read,cache_creation}_tokens`
      across its transcript (capped at 50k lines). Both land in the existing
      `detail` line, same style as Cline/Grok's already-there token counts. No
      local $ price table exists for Claude/Codex/Grok, so no cost figure was
      invented for them. Covered by `test_sessions_tokens.py`.
- [x] Click-to-expand: tapping a row's *title* (not the row, not the resume
      button) toggles clipped ↔ `fullTitle`, on all four frontends — a nested
      `MouseArea`/`.onTapGesture` scoped to just the title text/`Text` element.
- [x] Sticky Sessions header: the row list is now its own bounded (max 360px),
      independently-scrollable box (`Flickable` w/ `QC.ScrollBar` on Hyprland/
      Windows, `QQC2.ScrollView` on KDE, `ScrollView`/`LazyVStack` on macOS) so
      the title/count/search bar above it — and, since the popup's own height
      no longer balloons with 60 rows, the provider tab strip above *that* —
      stay visible instead of scrolling away. Verified visually on Hyprland
      (screenshot agent): header pinned, list capped, no double-scrollbar
      fight, nothing clipped mid-row.
- [x] Resume button icon changed from ⧉/▶ to a terminal glyph on every
      frontend (`utilities-terminal` KDE, `❯_` Hyprland/Windows, SF Symbol
      `terminal` macOS) — confirmed via 8x zoom crop on Hyprland, no tofu
      boxes.
- [x] Search bar (client-side text filter, title/sessionName/detail/provider)
      added to the Sessions tab on all four frontends.
- [x] Default Views toggles flipped: Sessions on by default, Overview/Spend
      off (`FeatureTabs.js`, `config/main.xml`, Hyprland/Windows settings
      defaults, macOS `SettingsStore`).
- [x] **Panel pill / tray icon fix**: while a feature tab (Overview/Spend/
      Sessions) is active, the floating pill (Hyprland, Windows) and the
      compact panel (KDE) used to show "—"/no data, since those tabs have no
      percentage of their own. Added `lastProviderId` (tracks the last real
      provider tab selected, via the existing `onActiveIdChanged`/
      `onActiveTabChanged` handler — **not** a second handler, QML errors on
      two of those on the same property, caught via a live-reload check) and
      a `pillProvider()`/`panelTab` fallback so the pill keeps showing that
      provider's data instead of going blank. macOS never had this bug —
      `AppModel.selectedID` was already independent of `featureView` by
      design. Fixed in `hyprland/AiUsageShell.qml`, `windows/qml/Main.qml`,
      `package/contents/ui/main.qml`.
- [x] macOS provider-icon fix attempt (`swift run` dev builds show a plain dot
      instead of the real logo, since there's no compiled asset catalog
      outside `scripts/build-app.sh`'s packaged `.app`): symlinked
      `package/contents/icons` into `macos/Sources/AIUsage/Resources`,
      declared it as an SPM resource in `Package.swift`, and
      `Artwork.providerImage()` now falls back to loading the raw SVG via
      `Bundle.module` (AppKit's native SVG `NSImage` support, macOS 12+) when
      the compiled catalog isn't found. Doesn't touch the packaged-app path at
      all (`NSImage(named:)` still wins there first). **Unverified — Swift
      doesn't compile on this Linux box.** Try `swift run` on a Mac.
- [x] CI: `.github/workflows/macos.yml`'s `app` job now posts a PR comment
      with 4 of the 11 screenshots (`popover-expanded-{light,dark}`,
      `settings-{light,dark}`) inlined as base64 data URIs, linking to the
      full `screenshots` artifact for the rest. Updates its own earlier
      comment on a rerun rather than stacking new ones (`<!-- macos-screenshots
      -->` marker). `continue-on-error: true` — never fails the build. Scoped
      `pull-requests: write` to just that job. **Known limitation, not fixed**:
      `pull_request`-triggered runs from a fork get a read-only token by
      GitHub's own design, so this silently no-ops (not fails) on external
      contributors' PRs; switching to `pull_request_target` would fix that but
      opens a real "pwn request" risk (untrusted fork code running with
      write-scoped secrets) not worth taking here. YAML validated with
      `python3 -c "import yaml; yaml.safe_load(...)"`; the embedded JS syntax-
      checked with `node --check`. **Not run on real CI** — first PR that
      touches `macos/` will be the real test.

## Open

### Housekeeping
- [ ] Nothing is committed yet — committing manually at the end. The currently
      *staged* index already bundles an unrelated Cursor on-demand-spend fix together
      with the Sessions/Overview/Spend feature-tabs work; this session's additions
      (resume button UI, macOS compile fix, `test_sessions_open.py`, docs) are unstaged
      on top. `git diff --cached <file>` vs `git diff <file>` tells the two eras apart
      per file if it's worth splitting before pushing.

