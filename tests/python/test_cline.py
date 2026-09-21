import json
import math
import os
import tempfile
import unittest
from unittest import mock

from _support import REPO  # noqa: F401
from aiusage import envelope, sessions
from aiusage.normalize.cline import normalize_cline
from aiusage.providers import cline

_MISSING = object()


class ClineRegressionTest(unittest.TestCase):
    def _write_record(self, root, directory, session_id, cost=_MISSING):
        session_dir = os.path.join(root, directory)
        os.makedirs(session_dir)
        record = {
            "started_at": "2026-09-17T00:00:00Z",
            "workspace_root": f"/workspaces/{directory}",
            "session_id": session_id,
            "metadata": {"aggregateUsage": {"inputTokens": 100, "outputTokens": 10}},
        }
        if cost is not _MISSING:
            record["metadata"]["aggregateUsage"]["totalCost"] = cost
        with open(os.path.join(session_dir, directory + ".json"), "w", encoding="utf-8") as stream:
            json.dump(record, stream)

    def test_provider_cost_is_not_local_session_actual(self):
        cases = (
            ("missing", _MISSING, None),
            ("zero", 0, None),
            ("negative", -0.5, None),
            ("nan", math.nan, None),
            ("positive_infinity", math.inf, None),
            ("negative_infinity", -math.inf, None),
            ("positive", 0.42, None),
        )
        for name, cost, expected in cases:
            with self.subTest(name=name):
                with tempfile.TemporaryDirectory() as root:
                    self._write_record(root, "session", "recorded-session", cost)
                    with mock.patch.dict(os.environ, {"CLINE_SESSIONS_DIR": root}):
                        entry = sessions._cline_entries()[0]
                if expected is None:
                    self.assertEqual(entry["costStatus"], "unavailable")
                    self.assertNotIn("costUSD", entry)
                else:
                    self.assertEqual(entry["costStatus"], "exact")
                    self.assertEqual(entry["costUSD"], expected)

    def test_provider_aggregate_is_not_reused_as_local_actual(self):
        record = {
            "startedAt": 1_789_047_000,
            "endedAt": 1_789_047_600,
            "provider": "cline",
            "model": "anthropic/claude-sonnet-4.5",
            "workspace": "synthetic-workspace",
            "input": 100,
            "output": 50,
            "cacheRead": 20,
            "cacheWrite": 10,
            "cost": 0.55,
        }
        provider = normalize_cline({"now": 1_789_047_600, "inputs": {"usage": {"sessions": [record]}}})
        with (
            mock.patch.object(
                sessions,
                "get_cline_session_records",
                return_value=[{**record, "sessionId": "synthetic-session"}],
            ),
            mock.patch.object(
                sessions.pricing,
                "cached_catalog",
                return_value={"anthropic": {"claude-sonnet-4.5": {"input": 2, "output": 8, "cached": 0.2}}},
            ),
        ):
            local_session = sessions._cline_entries()[0]
            with mock.patch("aiusage.sessions.all_session_rows", return_value=[local_session]):
                local_spend = envelope._local_spend()

        self.assertEqual(provider["details"]["stats"]["totalCostUSD"], 0.55)
        self.assertEqual(local_session["costProvenance"], "estimated")
        self.assertAlmostEqual(local_session["costUSD"], 0.000584)
        self.assertEqual(local_spend["actual"], {"costStatus": "unavailable"})
        self.assertEqual(local_spend["estimated"]["totalUSD"], 0.000584)

    def test_equal_started_at_records_keep_their_recorded_ids(self):
        with tempfile.TemporaryDirectory() as root:
            self._write_record(root, "z-session", "recorded-z", 0.1)
            self._write_record(root, "a-session", "recorded-a", 0.2)
            with (
                mock.patch.dict(os.environ, {"CLINE_SESSIONS_DIR": root}),
                mock.patch.object(cline.os, "listdir", side_effect=[["z-session", "a-session"], ["a-session", "z-session"]]),
            ):
                entries = sessions._cline_entries()

        keys_by_title = {entry["title"]: entry["openKey"] for entry in entries}
        self.assertEqual(keys_by_title["a-session"], sessions._open_key("cline", "recorded-a"))
        self.assertEqual(keys_by_title["z-session"], sessions._open_key("cline", "recorded-z"))


if __name__ == "__main__":
    unittest.main()
