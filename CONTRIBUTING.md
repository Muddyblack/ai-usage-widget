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
| gettext (`gettext`, `msgfmt`, `xgettext`, `msgmerge`, `msgcat`, `msgattrib`) | compiling translations in `./test_install.sh`, `make view`, `make pack`; `make translations` |
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

## Linux development shell

Install `direnv` outside the flake using your operating system's package
manager. From the repository root, run `direnv allow` once; entering the
repository then activates `devShells.default` through the tracked `.envrc`.
Without direnv, run `nix develop` directly.

After changing `flake.nix` or pulling updates, run `direnv reload` (or
`direnv allow`) so nix-direnv refreshes its cached shell. `direnv` itself stays
installed outside the flake.

The usual Linux checks and workflows are:

```bash
make test
make test-py
make lint-py
make translations
make check-translations
make view
make pack
nix run .#cli
nix run .#hyprland
```

## Optional profiling and debugging

The commands below are optional: use them when investigating a slow test,
frontend, tray helper, or process interaction. The Linux shell includes the
tools; the Windows shell does not.

| Area | Tools and examples |
|---|---|
| **Python backend and tests** | `pyinstrument -r text -m unittest discover -s tests/python`; `mprof` from `memory-profiler` (`mprof run --include-children python3 -m unittest discover -s tests/python`, then `mprof plot`); built-in `python3 -m cProfile -s cumulative -m unittest discover -s tests/python` for zero-dependency function-level profiling; `perf record --call-graph dwarf -- python3 -m unittest discover -s tests/python` then `perf report`. The dev-shell profilers use the same Python interpreter as `python3`; the backend remains standard-library-only at runtime. The pinned nixpkgs has no usable third-party line profiler package because its package tests fail. `py-spy` is also unavailable in the pinned nixpkgs. |
| **JavaScript shared tests** | Node.js has the built-in `--cpu-prof`, `--heap-prof`, and `--inspect` facilities: `node --cpu-prof --test tests/*.test.js`, `node --heap-prof --test tests/*.test.js`, or `node --inspect --test tests/*.test.js`. No extra npm dependency is needed. |
| **QML/Qt and the C++ tray helper** | Use `perf`, Hotspot, Heaptrack, Valgrind, and GDB: `perf record --call-graph dwarf -- nix run .#hyprland`; open the result with `hotspot perf.data`; collect allocations with `heaptrack nix run .#hyprland`; or debug a built tray-helper command with `valgrind --leak-check=full <tray-helper-command>` and `gdb --args <tray-helper-command>`. Hotspot and Heaptrack analysis require a graphical session. |
| **Shell, process, and IPC behavior** | `strace -f -e trace=process,ipc -o /tmp/ai-usage.strace make test`; `perf stat -d make test`. These are useful for the shell launchers, file/SQLite readers, subprocesses, and test IPC. |

`perf` may require kernel permissions such as `kernel.perf_event_paranoid`
adjustments, and recording adds runtime overhead. `strace` and Valgrind may be
limited by ptrace/security restrictions. Use the lightest command that answers
the question, especially for timing-sensitive behavior.

### Opt-in deterministic benchmarks

The benchmark suite is opt-in and is not part of `make test`, `make test-py`,
the default target, or CI. With direnv enabled from the repository root, run:

```bash
direnv allow
make benchmark
```

The same target can run without an interactive shell using
`nix develop --command make benchmark`. The scripts can also be run directly:

```bash
node benchmarks/history.js
python3 benchmarks/history_persistence.py
python3 benchmarks/session_index.py
```

Each script uses only deterministic synthetic data. The persistence and session
index cases use temporary directories that are cleaned automatically; no network,
provider, user, or XDG state is read or written, and no output artifacts are
created. Output is JSON Lines containing median nanoseconds. Timing varies with
the machine and current load, so the suite has no pass/fail thresholds and its
numbers should not be treated as portable performance claims.

The scope is JavaScript history `union()` and `normalize()`, Python history
`autosave`, and session-index initial `reconcile()` plus a fixed non-empty
substring `query()` at the documented point counts.

The Windows tray app is a separate shell: use `nix develop .#windows`, then
run `python windows/app.py` (or `make run-windows`). The macOS frontend is a
separate native workflow using Swift/Xcode tooling, including `make macos` and
`make macos-test`; see [`docs/macos.md`](docs/macos.md).

### Performance captures and per-wave acceptance

Performance comparisons are opt-in local evidence, not CI gates. `make help`
lists the existing `benchmark` target. `make test` and `make test-py` do not run
benchmarks, and neither CI nor this documentation adds timing thresholds.
Start from the repository root. Keep each change wave in its own evidence
directory; never replace an earlier wave's records:

```bash
EVIDENCE=.omo/evidence/performance-hardening/waveN/task-N
mkdir -p "$EVIDENCE"
```

Capture the same command, fixture, dimensions, sample count, and declared state
before and after the change. The harness defaults to five samples; this explicit
form records that default and retains each sample's raw output:

```bash
python3 benchmarks/measure_performance.py capture \
  --command "make benchmark" \
  --fixture synthetic-benchmark-suite \
  --fixture-dimension records=15 \
  --warmth warm --cache-state unknown --samples 5 \
  --output "$EVIDENCE/before.json" \
  --raw-output-dir "$EVIDENCE/before-raw"

# Make the change under test, then repeat the exact capture command with
# after.json and after-raw in place of before.json and before-raw.

python3 benchmarks/measure_performance.py compare \
  --before "$EVIDENCE/before.json" --after "$EVIDENCE/after.json" \
  --output "$EVIDENCE/comparison.json"
```

Capture runs the command five separate times. For this suite, each output line
is one in-process benchmark record. Compare each matching record's
`median_ns`; the harness also reports median, p95, minimum, and maximum across
the five samples. `samples[*].duration_ns` is whole-command launcher time,
separate from `records[*].median_ns`, the benchmark's in-process time. Do not
compare launcher time as though it were the inner operation. RSS is recorded
with availability, unit, source, and scope metadata; it can be unavailable
(`rss.available=false`, with null per-sample values), which is missing memory
data, not a zero-byte result.

Always record what `--fixture` names, its dimensions (for this suite, 15 JSONL
records per invocation), `--warmth`, and `--cache-state`. Warmth describes the
benchmark execution conditions; cache state describes the relevant cache
contents. They are separate declarations, not inferred measurements. Use
`cold` or `warm` only when the setup actually establishes that state. If the
state cannot be established, say `unknown`; compare only captures with matching
fixture, dimensions, warmth, cache state, command, metric, and requested sample
count. Do not combine cold and warm captures or launcher and in-process metrics.

For existing JSONL files instead of running a command again, use `summarize`
with one `--input` per sample and the same metadata flags, followed by the same
`compare` command. For example, task-1's preserved five runs can be summarized
without rewriting them:

```bash
python3 benchmarks/measure_performance.py summarize \
  --input .omo/evidence/performance-hardening/wave0/task-1/benchmark-1.stdout \
  --input .omo/evidence/performance-hardening/wave0/task-1/benchmark-2.stdout \
  --input .omo/evidence/performance-hardening/wave0/task-1/benchmark-3.stdout \
  --input .omo/evidence/performance-hardening/wave0/task-1/benchmark-4.stdout \
  --input .omo/evidence/performance-hardening/wave0/task-1/benchmark-5.stdout \
  --command "make benchmark" --fixture task-1-make-benchmark \
  --fixture-dimension iterations=7 --fixture-dimension warmups=3 \
  --fixture-dimension records=15 --warmth warm --cache-state unknown \
  --samples 5 --output "$EVIDENCE/before.json" \
  --raw-output-dir "$EVIDENCE/before-raw"
```

Summarized output files remain untouched. `summarize` treats each input file as
one sample and does not invent command duration or RSS data absent from those
files. Compare only with an after-capture made for the same fixture and declared
state.

#### Interpretation and required wave record

The capture/comparison verdict checks data completeness and comparability, not
whether a change is fast enough. A `pass` means the reports are structurally
valid and comparable, not that a performance goal was met. For each applicable
metric and fixture, a wave's local acceptance goal is at least 20% median
improvement in its named target, with no more than 10% median regression in
protected metrics. Treat those percentages as review guidance for controlled
local comparisons, never as a flaky CI threshold. State the measured deltas and
the acceptance decision in the wave record, even when the result misses the
goal.

Save a record at
`.omo/evidence/performance-hardening/waveN/task-N-performance-hardening.md`
alongside the capture JSON, comparison JSON, raw outputs, and test logs. Include:

- wave/task and change scope, plus the task-1 ownership baseline when the
  checkout already had dirty files;
- exact commands, working directory, declared fixture/dimensions, warmth, cache
  state, metric, sample count, tool/runtime/platform versions, and exit codes;
- before/after median, p95, minimum, maximum, percentage deltas for target and
  protected metrics, RSS availability, comparison verdict, and the acceptance
  decision with rationale;
- required functional tests and their counts, platform constraints, and any
  `BLOCKED` checks;
- rollback decision and action, or why rollback was not needed; retain both
  pre-change and post-change evidence regardless of the decision.

Malformed JSONL, an absent or malformed required field, fewer than five samples,
or mismatched fixture/dimensions/cache state/warmth/command/metric is not a pass.
For example, malformed JSONL produces a non-pass reason such as
`malformed_jsonl`; missing samples produce `missing_sample`; unequal comparison
metadata produces a reason such as `fixture_mismatch` or `cache_state_mismatch`.
The harness writes a non-pass report and exits 1 for these rejected reports
(invalid command-line or file errors may exit 2). Do not discard the report or
reinterpret a partial comparison as acceptance.

Platform test availability is part of the evidence. On a machine with Qt
available, run the Python suites with the required frontend flag so a Qt skip
cannot look green:

```bash
QT_QPA_PLATFORM=offscreen REQUIRE_FRONTEND_QT=1 \
  python3 -m unittest discover -s tests/python -v
```

When Swift is installed, run `swift test --package-path macos` (or
`make macos-test`). If Qt or Swift is unavailable, mark that verification
`BLOCKED` and name the missing dependency. A skipped Qt suite or unavailable
Swift toolchain is never a pass, and it does not silently satisfy release
verification.

If acceptance fails or a protected metric exceeds the 10% regression policy,
record the result and rollback decision. Revert only the wave's attributable
change using its reviewed patch or change-specific revert, not a broad worktree
reset. Preserve pre-existing dirty files identified by the task-1 ownership
artifacts, keep all raw evidence, then rerun the relevant functional tests and
capture the reverted state if it is used as the accepted result. Do not edit
task-1 baseline evidence to make the comparison appear clean.

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

For provider defaulting and detection, follow the complete checklist in
[`docs/provider-detection.md`](docs/provider-detection.md). It covers
`config.py`, `collect.py`, `envelope.py`, Plasma KConfig, `ProviderRegistry.js`,
`SettingsStore.swift`, fixtures, tests, and every affected document. A new
provider must not be called automatically detected unless it is in the backend
`AUTO_DETECT_PROVIDERS` allowlist and has stat-only, no-network, no-credential-read
tests.

For behavior shared by frontends, add a case to
[`tests/behavior/scenarios.json`](tests/behavior/scenarios.json). The
[behavioral test guide](tests/behavior/README.md) explains how Python, Plasma,
Hyprland/Windows and Swift consume the same scenarios and how to run the tests.

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
