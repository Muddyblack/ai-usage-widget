# The macOS frontend

A menu bar app in Swift, on the same Python backend every other frontend of
this widget uses. `docs/macos.md` has the reasoning, the paths, and the build
and distribution notes; this is the map of the directory.

```
Package.swift             SwiftPM: one executable, one test target, macOS 13+
Sources/AIUsage/
  App/                    the delegate, the model, the settings window, and the
                          --selftest / --screenshot modes
  Backend/                the JSON contract, the backend subprocess, the shared
                          settings file and the shared usage history
  MenuBar/                NSStatusItem with an attributed title, and the
                          NSPopover under it
  Views/                  the popover, its quota rows, the chart, the settings
  Support/                artwork, countdowns, the login item
Tests/AIUsageTests/       the parts with no window in them
packaging/                launcher and build dependencies for freezing the shared backend
scripts/build-app.sh      SwiftPM + actool + PyInstaller -> AI Usage.app
```

Screenshot demo data is shared with Windows in
[`scripts/demo-envelope.py`](../scripts/demo-envelope.py).

CI lives in [`.github/workflows/macos.yml`](../.github/workflows/macos.yml).

## Running it from a checkout

```bash
swift run --package-path macos
```

With no bundle around it there is no frozen backend, so it runs against
`package/contents/tools/sh/get-ai-usage` in this checkout — which needs a
`python3` on PATH. `AI_USAGE_BACKEND` overrides that.

Two things only work from a real bundle, and report themselves as unavailable
otherwise: "Open at Login" (`SMAppService` needs a bundle identifier) and the
provider logos (they live in an asset catalog `actool` compiles at bundle
time). Use `scripts/build-app.sh --skip-backend` for a bundle that still runs
against the checkout.

## The rule that keeps this affordable

This frontend renders the **provider-agnostic** core of
`docs/provider-contract.md`: `summary`, `quotaWindows`, `chartWindows`,
`slots`, `historyValues`, and the shared `details.status`. It also reads the
generic provider cost figures under `details`, plus the shared `localSpend` and
session cost fields for the Usage & Spend and Sessions views. A provider added
to the backend still shows up in the core views with no Swift change; only a
new contract field or provider-specific presentation needs one.

So: no provider names in `Views/`, no per-provider cases, no icon table — the
contract carries the label, the accent, the icon filename and the rows. The
one place provider ids appear is `SettingsStore.allProviders`, so the settings
window can offer a provider the backend has not reported yet; a test in
`tests/python/test_macos_contract.py` checks that list against the backend's,
along with the field names and the severity thresholds, because this is the
one frontend that cannot be compiled on the machine it is developed from.
