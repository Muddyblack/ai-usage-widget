# Terminal frontend

`ai-usage-cli` renders the same provider data as a table, with no Plasma,
Quickshell or compositor involved. It is the way to use this on a desktop the
widget cannot be installed on — Plasma 5, GNOME, XFCE — as well as over SSH, in
a shell prompt, or in a status bar.

## Getting it on PATH

```bash
# From a cloned checkout: put the tools on PATH …
export PATH="$PWD/package/contents/tools/sh:$PATH"

# … or link just the frontend (it resolves symlinks to find its package)
ln -s "$PWD/package/contents/tools/sh/ai-usage-cli" ~/.local/bin/ai-usage-cli

# … or, on NixOS, run it straight from the flake without installing anything
nix run .#cli
nix run github:Muddyblack/ai-usage-widget#cli
```

If the widget is already installed, its settings page lists the path under
**Terminal** with a copy button, so the plasmoid directory does not have to be
hunted down by hand.

## Usage

```bash
ai-usage-cli                        # every enabled provider
ai-usage-cli --provider claude,zai  # a subset, ignoring the toggles
ai-usage-cli --compact              # one line, for status bars
watch -n 300 ai-usage-cli           # refresh in place
get-ai-usage --all | ai-usage-cli   # render an envelope you already fetched
```

```
PROVIDER  PLAN          WINDOW             USAGE                NOTE                      RESET
────────────────────────────────────────────────────────────────────────────────────────────────────────
Claude    max           5-hour session     [██░░░░░░░░]  23%    120000 / 500000 tokens    Jul 19, 17:00
Claude    max           7-day window       [██████░░░░]  61%    3000000 / 5000000 tokens  Jul 25, 17:00
────────────────────────────────────────────────────────────────────────────────────────────────────────
Z.AI      pro           5-hour tokens      [██░░░░░░░░]  25%    250 / 1000 tokens         Jul 25, 20:20
Z.AI      pro           Monthly tools      [████░░░░░░]  40%    60 remaining              Jul 25, 21:20
────────────────────────────────────────────────────────────────────────────────────────────────────────
Kimi      Moonshot API  Available balance  $49.59
────────────────────────────────────────────────────────────────────────────────────────────────────────
Copilot   —             —                  Copilot: no token configured
```

Colour follows the same thresholds as the panel indicators (amber from 70%, red
from 90%) and switches off automatically when the output is not a terminal, or
when `NO_COLOR` is set. `--color always|never` overrides that, and `--ascii`
replaces the box drawing for terminals without a UTF-8 locale. Columns that stay
empty — a provider set with no reset times, say — are dropped rather than
printed blank. A provider that cannot report keeps its row and shows the reason,
so a missing key does not look like a service you never enabled.

## Configuration

Without a widget there is no settings page to write the config, so create it
once by hand at `~/.config/ai-usage-widget/hyprland-settings.json` (or under
`$XDG_CONFIG_HOME`; `AI_USAGE_CONFIG` overrides the path). Providers not listed
default to on; credentials go in `keys`, and the `WIDGET_*` environment
variables win over the file if you would rather not store them:

```json
{
  "providers": { "claude": true, "zai": true, "kimi": true, "openai": false },
  "keys": { "zai": "…", "moonshot": "…" }
}
```

Claude needs no key — a local Claude Code login is enough. See
[`providers.md`](providers.md) for what each of the others reads.
