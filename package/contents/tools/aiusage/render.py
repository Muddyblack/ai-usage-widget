"""Terminal rendering of the provider contract.

Presentation only, the same rule the two QML frontends follow: every function
here takes a finished envelope and returns text. No network, no config, no
provider knowledge, no quota arithmetic — see docs/provider-contract.md for the
schema being rendered.

ANSI sequences are applied last, after column widths have been measured on the
plain text, so colour can never shift the layout.
"""

from .contract import num, pct_clamp

# The panel indicators in both frontends switch colour at these percentages
# (package/contents/ui/PanelSlot.qml, ui/PanelSlot.qml,
# package/contents/ui/main.qml). Kept identical here so a quota that reads red
# in the panel does not read yellow in the terminal. Below the warning
# threshold the frontends use the plain text colour, and so does this.
WARN_PCT = 70
DANGER_PCT = 90

METER_WIDTH = 10

_ANSI = {
    "bold": "\033[1m",
    "dim": "\033[2m",
    "red": "\033[31m",
    "yellow": "\033[33m",
}
_RESET = "\033[0m"

HEADERS = ("PROVIDER", "PLAN", "WINDOW", "USAGE", "NOTE", "RESET")

# Columns dropped entirely when no row fills them, rather than printing a
# header over a column of blanks. USAGE is kept even if a provider reports
# nothing, because its error text goes there.
OPTIONAL_COLUMNS = (1, 4, 5)


class Style:
    """Applies ANSI names, or returns the text untouched when colour is off."""

    def __init__(self, enabled):
        self.enabled = enabled

    def __call__(self, text, *names):
        names = [n for n in names if n]
        if not self.enabled or not names or text == "":
            return text
        return "".join(_ANSI[n] for n in names) + text + _RESET


def _cell(*fragments):
    """A cell as (text, *styles) fragments — width is measured on text alone."""
    return list(fragments)


def _width(cell):
    return sum(len(f[0]) for f in cell)


def _paint(cell, style, width):
    body = "".join(style(f[0], *f[1:]) for f in cell)
    return body + " " * max(0, width - _width(cell))


def _level(pct):
    """Colour name for a percentage, or "" below the warning threshold."""
    if pct >= DANGER_PCT:
        return "red"
    if pct >= WARN_PCT:
        return "yellow"
    return ""


def _pct_text(pct):
    return f"{pct:g}%"


def _meter(pct, unicode_ok, level):
    full, empty = ("█", "░") if unicode_ok else ("#", "-")
    filled = int(round(pct / 100.0 * METER_WIDTH))
    filled = max(0, min(METER_WIDTH, filled))
    # A quota that has been touched at all should not render as an empty bar.
    if filled == 0 and pct > 0:
        filled = 1
    frags = [("[", "dim")]
    if filled:
        frags.append((full * filled, level))
    if filled < METER_WIDTH:
        frags.append((empty * (METER_WIDTH - filled), "dim"))
    frags.append(("]", "dim"))
    return frags


def _provider_rows(p, unicode_ok):
    label = p.get("label") or p.get("id") or "?"
    summary = p.get("summary") or {}
    windows = p.get("quotaWindows") or []

    if p.get("ok") is not True or not windows:
        # A provider that cannot report still gets a row. A missing key or an
        # offline endpoint is precisely what someone runs this to find out, and
        # dropping the row would make the provider look absent instead of broken.
        reason = (p.get("error") or "").strip() or (summary.get("detail") or "").strip() or "no data"
        return [[_cell((label, "bold")), _cell(("—", "dim")), _cell(("—", "dim")), _cell((reason, "red")), _cell(), _cell()]]

    plan = _cell(((summary.get("detail") or "").strip(),))
    if p.get("stale") is True:
        plan.append((" (stale)", "dim"))

    rows = []
    for w in windows:
        detail = (w.get("detail") or "").strip()
        note = detail
        if w.get("available") is False:
            usage = _cell(("—", "dim"))
        elif w.get("showMeter"):
            pct = pct_clamp(num(w.get("pct")))
            level = _level(pct)
            usage = _meter(pct, unicode_ok, level)
            usage.append((" " + _pct_text(pct).rjust(4), level))
        else:
            # Providers reporting money rather than a percentage (a balance, a
            # spend) put the value itself in `detail` and clear showMeter, so it
            # becomes the usage value rather than a note beside it.
            usage = _cell((detail or "—",))
            note = ""

        # An explicit note wins over the derived one, which is what lets a
        # meterless row keep an aside after `detail` became the value.
        if w.get("note"):
            note = str(w["note"]).strip()

        rows.append(
            [
                _cell((label, "bold")),
                list(plan),
                _cell(((w.get("label") or w.get("key") or "").strip(),)),
                usage,
                _cell((note, "dim")),
                _cell(((w.get("resetText") or "").strip(), "dim")),
            ]
        )
    return rows


def render_table(env, style, unicode_ok=True):
    """The full table: one row per quota window, grouped by provider."""
    groups = [_provider_rows(p, unicode_ok) for p in (env.get("providers") or [])]
    groups = [g for g in groups if g]
    if not groups:
        return "no providers selected — enable some in the settings file or pass --provider"

    keep = [i for i in range(len(HEADERS)) if i not in OPTIONAL_COLUMNS or any(_width(row[i]) for g in groups for row in g)]
    groups = [[[row[i] for i in keep] for row in g] for g in groups]

    header = [_cell((HEADERS[i], "bold")) for i in keep]
    columns = len(keep)
    widths = [max(_width(r[i]) for r in [header] + [row for g in groups for row in g]) for i in range(columns)]
    rule = ("─" if unicode_ok else "-") * (sum(widths) + 2 * (columns - 1))

    def line(row):
        # The last column is not padded, so no row carries trailing whitespace.
        return "  ".join(_paint(c, style, widths[i]) if i < columns - 1 else _paint(c, style, 0) for i, c in enumerate(row)).rstrip()

    out = [line(header), style(rule, "dim")]
    for i, g in enumerate(groups):
        if i:
            out.append(style(rule, "dim"))
        out.extend(line(row) for row in g)
    return "\n".join(out)


def render_compact(env, style):
    """One line, headline value per provider — for status bars and prompts."""
    parts = []
    for p in env.get("providers") or []:
        label = p.get("label") or p.get("id") or "?"
        summary = p.get("summary") or {}
        if p.get("ok") is not True:
            parts.append(label + " " + style("—", "dim"))
            continue
        text = (summary.get("text") or "").strip() or "—"
        parts.append(label + " " + style(text, _level(pct_clamp(num(summary.get("pct"))))))
    return "  ".join(parts)
