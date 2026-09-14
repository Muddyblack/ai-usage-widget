# Shared frontend behavior

`scenarios.json` is the reviewed source of expected behavior. Each case has
either a raw backend input or a deliberately sparse frontend envelope, plus
expected visible row keys/values, panel text and history values. Keep these
expectations explicit; do not regenerate them from the implementation.

`scripts/frontend-fixtures.py` normalizes raw inputs with the production Python
backend and exports the envelopes with their expectations. It does not collect
credentials, read live usage or contact providers. All consumers use this same
export, so backend changes reach frontend tests immediately.

The initial cases cover Codex weekly-only plans, both API formats' empty
five-hour placeholders, real zero usage, missing resets, Spark and missing or
unavailable fields. Add a regression case here when behavior must agree across
frontends; extend the adapters when adding coverage for another provider.

Consumers:

- Python checks backend output against the expectations.
- Node executes Plasma's actual `applyOpenAi` and Windows' `publishTray` QML
  functions and the shared history collector. These test data mapping, not
  Plasma rendering; the desktop host is stubbed to avoid polling or side effects.
- Qt instantiates the production `UsageRows.qml` used by both Hyprland and
  Windows, checks actual delegate counts/values, and reuses the component across
  scenarios to catch stale rows. QML warnings fail the test.
- Swift decodes the same envelopes and tests the visible-row model used by
  `UsageView`, menu-bar readings and decoded history values.

Run from the repository root:

```sh
python3 -m unittest discover -s tests/python -p test_frontend_behavior.py
node --test tests/frontend-behavior.test.js
swift test --package-path macos  # macOS
```

Qt requires PySide6 (`nix develop .#windows` supplies it). The portable suite
skips Qt when absent; the Windows/Linux CI matrix sets `REQUIRE_FRONTEND_QT=1`
so missing Qt fails that job. Swift runs in macOS CI. Screenshot artifacts
remain available for visual review; these behavioral tests do not replace them.
