"""Mode-aware OpenCode normalization: Zen local-only vs Go account quota.

Zen mode renders the device-local session ledger and never invents an account
quota. Go mode renders the account-level rolling/weekly/monthly quota windows
reported by the Go usage endpoint, with three distinct persisted history
series, and stays Go even when the endpoint fails.
"""

import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest

from _support import TOOLS, IsolatedHomeTest, fixture
from aiusage import history
from aiusage.normalize.opencode import _GO_WINDOWS, normalize_opencode

NOW = 1_700_000_000

GO_BODY = {
    "usage": {
        "rolling": {"status": "ok", "percent": 42, "resetsAt": "2026-09-23T00:00:00Z"},
        "weekly": {"status": "ok", "percent": 61, "resetsAt": "2026-09-28T00:00:00Z"},
        "monthly": {"status": "ok", "percent": 33, "resetsAt": "2026-10-01T00:00:00Z"},
    }
}

_SESSION_SCHEMA = """
CREATE TABLE session (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    directory TEXT NOT NULL,
    time_created INTEGER NOT NULL,
    time_updated INTEGER NOT NULL
);
"""
_MESSAGE_SCHEMA = """
CREATE TABLE message (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    data TEXT NOT NULL
);
"""
_PART_SCHEMA = """
CREATE TABLE part (
    id TEXT PRIMARY KEY,
    message_id TEXT NOT NULL,
    data TEXT NOT NULL
);
"""


def _bucket(provider, model, input_tokens, output_tokens, cost):
    return {
        "provider": provider,
        "model": model,
        "input": input_tokens,
        "output": output_tokens,
        "cacheRead": 0,
        "cacheWrite": 0,
        "reasoning": 0,
        "costUSD": cost,
        "costStatus": "exact",
    }


def _session(session_id, last_activity, directory, usage):
    return {
        "id": session_id,
        "title": "Synthetic session",
        "directory": directory,
        "createdAt": last_activity,
        "lastActivity": last_activity,
        "usage": usage,
        "costUSD": sum(row.get("costUSD") or 0 for row in usage),
        "costStatus": "exact",
        "costProvenance": "catalog/local ledger",
    }


def _local_usage():
    return {
        "sessions": [
            _session(
                "session-1",
                NOW - 3600,
                "/synthetic/project",
                [_bucket("opencode", "gpt-test", 800, 100, 0.42)],
            )
        ]
    }


def _envelope(mode="zen", go_usage=None, go_error="", usage=None, now=NOW):
    return {
        "id": "opencode",
        "now": now,
        "inputs": {
            "usage": usage if usage is not None else {"sessions": []},
            "account": {"mode": mode, "goUsage": go_usage, "goError": go_error},
        },
    }


class OpenCodeNormalizeZenTest(unittest.TestCase):
    def test_zen_renders_local_activity_without_inventing_quota(self):
        r = normalize_opencode(_envelope(mode="zen", usage=_local_usage()))
        self.assertTrue(r["ok"])
        self.assertEqual(r["details"]["accountMode"], "zen")
        self.assertEqual(r["summary"]["pct"], 0)
        self.assertFalse(r["summary"]["hasChart"])
        self.assertIn("local Zen activity", r["summary"]["detail"])
        self.assertEqual(r["historyValues"], {})
        self.assertEqual(r["chartWindows"], [])
        self.assertTrue(r["quotaWindows"])
        for window in r["quotaWindows"]:
            self.assertFalse(window["showMeter"])

    def test_zen_without_local_sessions_is_an_error_not_a_quota(self):
        r = normalize_opencode(_envelope(mode="zen", usage={"sessions": []}))
        self.assertFalse(r["ok"])
        self.assertEqual(r["details"]["accountMode"], "zen")
        self.assertEqual(r["summary"]["detail"], "OpenCode: no local sessions yet")

    def test_opencode_missing_fixture_stays_zen_error(self):
        r = fixture("opencode-missing")
        self.assertFalse(r["ok"])
        self.assertEqual(r["details"]["accountMode"], "zen")


class OpenCodeNormalizeGoTest(unittest.TestCase):
    def test_go_valid_windows_render_meters_history_and_charts(self):
        r = normalize_opencode(_envelope(mode="go", go_usage=GO_BODY))
        self.assertTrue(r["ok"])
        self.assertEqual(r["details"]["accountMode"], "go")
        self.assertEqual(r["details"]["goError"], "")
        self.assertEqual(r["summary"]["pct"], 42)
        self.assertEqual(r["summary"]["text"], "42%")
        self.assertEqual(r["summary"]["detail"], "Rolling (5h)")
        self.assertTrue(r["summary"]["hasChart"])
        self.assertEqual(
            [w["key"] for w in r["quotaWindows"]],
            [key for _name, key, _label, _period in _GO_WINDOWS],
        )
        for window in r["quotaWindows"]:
            self.assertTrue(window["showMeter"])
            self.assertGreater(window["resetAt"], 0)
        self.assertEqual(
            r["historyValues"],
            {"opencode_go_rolling_pct": 42, "opencode_go_weekly_pct": 61, "opencode_go_monthly_pct": 33},
        )
        self.assertEqual(
            [w["id"] for w in r["chartWindows"]],
            ["opencode_go_5h", "opencode_go_24h", "opencode_go_7d", "opencode_go_30d"],
        )
        for window in r["chartWindows"]:
            self.assertIn(window["key"], r["historyValues"])

    def test_go_percent_is_clamped_to_0_100(self):
        body = {
            "usage": {
                "rolling": {"status": "ok", "percent": 150, "resetsAt": "2026-09-23T00:00:00Z"},
                "weekly": {"status": "ok", "percent": -5, "resetsAt": "2026-09-28T00:00:00Z"},
                "monthly": {"status": "ok", "percent": 33, "resetsAt": "2026-10-01T00:00:00Z"},
            }
        }
        r = normalize_opencode(_envelope(mode="go", go_usage=body))
        self.assertEqual(r["historyValues"]["opencode_go_rolling_pct"], 100)
        self.assertEqual(r["historyValues"]["opencode_go_weekly_pct"], 0)
        self.assertEqual(r["summary"]["pct"], 100)

    def test_go_missing_windows_are_not_fabricated_as_zero(self):
        body = {"usage": {"weekly": {"status": "ok", "percent": 61, "resetsAt": "2026-09-28T00:00:00Z"}}}
        r = normalize_opencode(_envelope(mode="go", go_usage=body))
        self.assertTrue(r["ok"])
        self.assertEqual(r["historyValues"], {"opencode_go_weekly_pct": 61})
        self.assertEqual([w["key"] for w in r["quotaWindows"]], ["opencode_go_weekly_pct"])
        self.assertEqual(r["summary"]["pct"], 61)
        self.assertEqual(r["summary"]["detail"], "Weekly (7d)")
        for window in r["chartWindows"]:
            self.assertIn(window["key"], r["historyValues"])

    def test_go_status_not_ok_windows_are_unavailable(self):
        body = {
            "usage": {
                "rolling": {"status": "exhausted", "percent": 100, "resetsAt": "2026-09-23T00:00:00Z"},
                "weekly": {"status": "ok", "percent": 61, "resetsAt": "2026-09-28T00:00:00Z"},
                "monthly": {"status": "ok", "percent": 33, "resetsAt": "2026-10-01T00:00:00Z"},
            }
        }
        r = normalize_opencode(_envelope(mode="go", go_usage=body))
        self.assertEqual(r["historyValues"], {"opencode_go_weekly_pct": 61, "opencode_go_monthly_pct": 33})
        self.assertEqual(r["summary"]["pct"], 61)

    def test_go_invalid_percent_types_are_unavailable(self):
        for bad in (True, "42", None, float("nan"), float("inf")):
            with self.subTest(percent=bad):
                body = {
                    "usage": {
                        "rolling": {"status": "ok", "percent": bad, "resetsAt": "2026-09-23T00:00:00Z"},
                        "weekly": {"status": "ok", "percent": 61, "resetsAt": "2026-09-28T00:00:00Z"},
                        "monthly": {"status": "ok", "percent": 33, "resetsAt": "2026-10-01T00:00:00Z"},
                    }
                }
                r = normalize_opencode(_envelope(mode="go", go_usage=body))
                self.assertEqual(r["historyValues"], {"opencode_go_weekly_pct": 61, "opencode_go_monthly_pct": 33})
                self.assertEqual(r["summary"]["pct"], 61)

    def test_go_no_usable_windows_is_an_error_not_zero(self):
        body = {
            "usage": {
                "rolling": {"status": "exhausted", "percent": 100, "resetsAt": "2026-09-23T00:00:00Z"},
                "weekly": {"status": "ok", "percent": True, "resetsAt": "2026-09-28T00:00:00Z"},
                "monthly": {"status": "ok", "percent": "33", "resetsAt": "2026-10-01T00:00:00Z"},
            }
        }
        r = normalize_opencode(_envelope(mode="go", go_usage=body))
        self.assertFalse(r["ok"])
        self.assertEqual(r["summary"]["detail"], "OpenCode Go: no usable quota windows")
        self.assertEqual(r["historyValues"], {})
        self.assertEqual(r["chartWindows"], [])

    def test_go_error_stays_go_mode_with_stable_message(self):
        r = normalize_opencode(_envelope(mode="go", go_usage=None, go_error="403 Forbidden"))
        self.assertFalse(r["ok"])
        self.assertEqual(r["details"]["accountMode"], "go")
        self.assertEqual(r["details"]["goError"], "403 Forbidden")
        self.assertEqual(r["summary"]["detail"], "OpenCode Go: 403 Forbidden")

    def test_go_malformed_payloads_are_errors(self):
        for go_usage in (None, [], "nope", {"usage": []}, {"usage": "x"}):
            with self.subTest(go_usage=go_usage):
                r = normalize_opencode(_envelope(mode="go", go_usage=go_usage))
                self.assertFalse(r["ok"])
                self.assertEqual(r["details"]["accountMode"], "go")

    def test_go_is_independent_of_local_sessions(self):
        r = normalize_opencode(_envelope(mode="go", go_usage=GO_BODY, usage={"sessions": []}))
        self.assertTrue(r["ok"])
        self.assertEqual(r["summary"]["pct"], 42)

    def test_go_reset_parsing_is_best_effort(self):
        body = {
            "usage": {
                "rolling": {"status": "ok", "percent": 42, "resetsAt": "2026-09-23T00:00:00Z"},
                "weekly": {"status": "ok", "percent": 61},
                "monthly": {"status": "ok", "percent": 33, "resetsAt": "not-a-date"},
            }
        }
        r = normalize_opencode(_envelope(mode="go", go_usage=body))
        self.assertTrue(r["ok"])
        windows = {w["key"]: w for w in r["quotaWindows"]}
        self.assertGreater(windows["opencode_go_rolling_pct"]["resetAt"], 0)
        self.assertEqual(windows["opencode_go_weekly_pct"]["resetAt"], 0)
        self.assertEqual(windows["opencode_go_monthly_pct"]["resetAt"], 0)


class OpenCodeHistoryModeSwitchTest(IsolatedHomeTest):
    def test_go_keys_survive_a_zen_poll_and_update_in_place(self):
        path = self.home / "usage-history.json"
        go = normalize_opencode(_envelope(mode="go", go_usage=GO_BODY))
        merged = history.save(str(path), [{"t": NOW, **go["historyValues"]}])
        self.assertEqual(merged[-1]["opencode_go_rolling_pct"], 42)

        zen = normalize_opencode(_envelope(mode="zen", usage=_local_usage()))
        merged = history.save(str(path), [{"t": NOW + 60, **zen["historyValues"]}])
        go_point = next(point for point in merged if point["t"] == NOW)
        self.assertEqual(go_point["opencode_go_rolling_pct"], 42)

        go2 = normalize_opencode(_envelope(mode="go", go_usage=GO_BODY))
        merged = history.save(str(path), [{"t": NOW + 120, **go2["historyValues"]}])
        latest = merged[-1]
        self.assertEqual(latest["opencode_go_rolling_pct"], 42)
        self.assertEqual(latest["opencode_go_weekly_pct"], 61)
        self.assertEqual(latest["opencode_go_monthly_pct"], 33)


class OpenCodeCliGoTest(IsolatedHomeTest):
    def test_cli_go_mode_renders_go_windows_without_leaking_the_key(self):
        secret = "sk-opencode-go-cli-secret"
        self.write(".local/share/opencode/auth.json", {"opencode-go": {"type": "api", "key": secret}})
        with tempfile.TemporaryDirectory() as root:
            db = os.path.join(root, "opencode.db")
            connection = sqlite3.connect(db)
            try:
                with connection:
                    connection.executescript(_SESSION_SCHEMA + _MESSAGE_SCHEMA + _PART_SCHEMA)
            finally:
                connection.close()
            fixture_path = os.path.join(root, "go-usage.json")
            with open(fixture_path, "w", encoding="utf-8") as fh:
                fh.write(json.dumps(GO_BODY))
            env = dict(os.environ)
            env["PYTHONPATH"] = TOOLS
            env["OPENCODE_DB"] = db
            env["OPENCODE_GO_USAGE_RESPONSE_FILE"] = fixture_path
            result = subprocess.run(
                [sys.executable, "-m", "aiusage", "--provider", "opencode"],
                env=env,
                capture_output=True,
                text=True,
                timeout=120,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["schemaVersion"], 1)
        self.assertEqual(payload["active"], "opencode")
        provider = payload["providers"][0]
        self.assertEqual(provider["id"], "opencode")
        self.assertEqual(provider["details"]["accountMode"], "go")
        self.assertEqual(provider["historyValues"]["opencode_go_rolling_pct"], 42)
        self.assertNotIn(secret, result.stdout)


if __name__ == "__main__":
    unittest.main()
