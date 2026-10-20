#!/usr/bin/env python3
"""A believable envelope built from the test fixtures, for screenshots.

The macOS frontend cannot be looked at from a Linux machine, and neither can a
CI runner sign in to fourteen AI services. So `--screenshot` is pointed at this
instead of the real backend: it prints the same contract-shaped envelope the
backend prints, assembled out of tests/fixtures, and a plausible usage history
to go with it. No credential is involved and nothing reaches the network.

    demo-envelope.py --all              the envelope
    demo-envelope.py history autoload   a history series for the chart
"""

import json
import math
import os
import sys
import time
from datetime import date, timedelta

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "backend"))

from tidesi.contract import finalize, remote_info  # noqa: E402
from tidesi.normalize import normalize  # noqa: E402

# One healthy provider of each interesting shape: percentage quotas with
# resets, a spend balance, and a provider that is signed out.
FIXTURES = ["claude-success", "openai-codex-success", "copilot-success", "antigravity-success", "cursor-success", "grok-missing"]


def envelope():
    now = int(time.time())
    providers = []
    for name in FIXTURES:
        path = os.path.join(ROOT, "tests", "fixtures", name + ".json")
        with open(path, encoding="utf-8") as fh:
            raw = json.load(fh)
        provider = finalize(normalize(raw))
        # The fixtures were recorded at a fixed instant; move their resets into
        # the future so the countdowns read like a live machine's.
        _refresh_times(provider, now)
        _add_remote(provider)
        if provider["id"] in ("claude", "openai"):
            # This demo represents subscription activity, without API billing.
            details = provider.get("details", {})
            details.pop("organizationUsage", None)
            details.pop("totalCostUSD", None)
            details.get("stats", {}).pop("totalCostUSD", None)
        elif provider["id"] == "cursor":
            details = provider.setdefault("details", {})
            details.setdefault("stats", {}).pop("totalCostUSD", None)
            for key in ("onDemandUsed", "onDemandSpendUSD", "onDemand"):
                details.pop(key, None)
        providers.append(provider)
    active = next((p["id"] for p in providers if p.get("ok")), "")
    return {"schemaVersion": 1, "updatedAt": now, "active": active, "providers": providers, "localSpend": demo_spend()}


def demo_spend():
    """Synthetic plan equivalents and metered costs, never local user data."""

    def entry(total, phase):
        weights = [1.1 + 0.65 * math.sin(i * 0.7 + phase) + (0.8 if i % 9 == 0 else 0) for i in range(30)]
        costs = [round(total * w / sum(weights), 2) for w in weights]
        costs[-1] = round(total - sum(costs[:-1]), 2)
        dates = [(date.today() - timedelta(days=29 - i)).isoformat() for i in range(30)]
        return {
            "costStatus": "exact",
            "costUSD": total,
            "dailyUSD": [{"date": d, "usd": c} for d, c in zip(dates, costs)],
            "dailyTokens": [{"date": d, "total": int(1600000 + 650000 * math.sin(i * 0.35 + phase))} for i, d in enumerate(dates)],
        }

    return {
        "subscription": {"costStatus": "exact", "providers": {"claude": entry(1290.10, 0), "openai": entry(760.98, 1)}},
        "estimated": {"costStatus": "exact", "providers": {"grok": entry(0.84, 2)}},
        "actual": {"costStatus": "exact", "providers": {"cursor": entry(18.42, 3)}},
    }


def _add_remote(provider):
    """The Remote tab: devices (Antigravity) and open sessions (Claude Code)
    the fixtures carry none of."""
    if provider["id"] == "antigravity":
        instances = [
            {"name": "work-laptop", "state": "online", "detail": "Online", "url": "https://antigravity.google.com"},
            {"name": "home-desktop", "state": "online", "detail": "Online · Busy", "url": "https://antigravity.google.com"},
            {"name": "cloudshell", "state": "offline", "detail": "Offline", "url": "https://antigravity.google.com"},
        ]
        remote = remote_info(
            "online",
            "Remote devices",
            "2 online · 3 devices",
            "https://antigravity.google.com",
            "Open antigravity.google.com ↗",
            "Select a device to open it in Antigravity.",
            instances,
        )
    elif provider["id"] == "claude":
        instances = [
            {"name": "ai-usage-widget", "detail": "~/projects/ai-usage-widget", "state": "busy", "url": "https://claude.ai/code"},
            {"name": "homelab", "detail": "~/projects/homelab", "state": "idle", "url": "https://claude.ai/code"},
        ]
        remote = remote_info(
            "online",
            "2 sessions open to other devices",
            "Started with /remote-control in Claude Code. Continue them from your phone or the browser.",
            "https://claude.ai/code",
            "Open claude.ai/code ↗",
            "",
            instances,
        )
    else:
        return
    provider.setdefault("details", {})["remote"] = remote


def _refresh_times(provider, now):
    provider["updatedAt"] = now
    for index, window in enumerate(provider.get("quotaWindows") or []):
        if window.get("resetAt"):
            window["resetAt"] = now + (2 * 3600 + 840) + index * 36 * 3600
            window["resetText"] = time.strftime("%b %d, %H:%M", time.localtime(window["resetAt"]))
    for window in provider.get("chartWindows") or []:
        if window.get("resetAt"):
            window["resetAt"] = now + 2 * 3600


def history():
    """Six hours of five-minute samples that climb and reset, so the chart has
    the shape a real one has rather than a straight line."""
    now_ms = time.time() * 1000
    points = []
    for step in range(72):
        t = now_ms - (72 - step) * 5 * 60 * 1000
        ramp = (step % 40) / 40
        points.append(
            {
                "t": t,
                "s": round(min(96, 8 + 88 * ramp * ramp), 1),
                "w": round(min(88, 30 + step * 0.8), 1),
                "cp": round(min(90, 12 + step * 1.1), 1),
                "cw": round(min(70, 20 + step * 0.6), 1),
                "gh": round(min(100, 5 + step * 1.3), 1),
                "cu": round(min(64, 3 + step * 0.85), 1),
            }
        )
    return {"ok": True, "data": points}


def main(argv):
    if argv and argv[0] == "history":
        command = argv[1] if len(argv) > 1 else ""
        if command == "autoload":
            print(json.dumps(history(), separators=(",", ":")))
        else:
            # autosave/seed: accept and echo nothing back, so a screenshot run
            # never touches the real history file.
            print(json.dumps({"ok": True, "empty": True}))
        return 0
    print(json.dumps(envelope(), separators=(",", ":"), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
