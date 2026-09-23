import datetime
import unittest

from _support import REPO  # noqa: F401  (ensures TOOLS is on sys.path)
from aiusage.stats import opencode_stats

NOW = 1_780_000_000
OWN_DATE = datetime.datetime.fromtimestamp(NOW - 3600).strftime("%Y-%m-%d")
UPSTREAM_DATE = datetime.datetime.fromtimestamp(NOW - 2 * 86400).strftime("%Y-%m-%d")


def _bucket(provider, model, *, input_tokens=0, output_tokens=0, cost=None):
    bucket = {
        "provider": provider,
        "model": model,
        "input": input_tokens,
        "output": output_tokens,
        "cacheRead": 0,
        "cacheWrite": 0,
        "reasoning": 0,
    }
    if cost is not None:
        bucket["costUSD"] = cost
    return bucket


def _session(session_id, last_activity, directory, usage):
    return {
        "id": session_id,
        "lastActivity": last_activity,
        "directory": directory,
        "usage": usage,
    }


class OpenCodeStatsTest(unittest.TestCase):
    def test_mixed_sessions_keep_only_opencode_usage(self):
        stats = opencode_stats(
            {
                "sessions": [
                    _session(
                        "mixed",
                        NOW - 3600,
                        "/projects/own",
                        [
                            _bucket("opencode", "subscription", input_tokens=10, output_tokens=20, cost=2.0),
                            _bucket("openai", "gpt-upstream", input_tokens=100, output_tokens=200, cost=5.0),
                        ],
                    ),
                ]
            },
            NOW,
        )

        self.assertEqual(set(stats["models"]), {"opencode/subscription"})
        self.assertEqual(stats["upstreamProviders"], [{"provider": "opencode", "tokens": 30, "cost": 2.0, "requests": 1, "costStatus": "exact"}])
        self.assertEqual(stats["totalTokens"], 30)
        self.assertEqual(stats["totalCostUSD"], 2.0)

    def test_upstream_only_sessions_are_excluded_from_activity(self):
        stats = opencode_stats(
            {
                "sessions": [
                    _session("own", NOW - 3600, "/projects/own", [_bucket("opencode", "free", output_tokens=7)]),
                    _session("upstream", NOW - 2 * 86400, "/projects/upstream", [_bucket("ollama-cloud", "llama", output_tokens=99)]),
                ]
            },
            NOW,
        )

        self.assertEqual(stats["totalSessions"], 1)
        self.assertEqual(stats["totalMessages"], 1)
        self.assertEqual(stats["topWorkspaces"], [{"name": "/projects/own", "sessions": 1}])
        self.assertEqual(stats["dailyTokens"], [{"date": OWN_DATE, "total": 7}])
        self.assertEqual(stats["dailySeries"], [{"date": OWN_DATE, "total": 7}])
        self.assertEqual(stats["periods"][0]["sessions"], 1)
        self.assertEqual(stats["periods"][0]["tokens"], 7)
        self.assertEqual(stats["periods"][-1]["sessions"], 1)
        self.assertEqual(stats["periods"][-1]["tokens"], 7)
        self.assertNotIn(UPSTREAM_DATE, {row["date"] for row in stats["dailyTokens"]})

    def test_own_subscription_and_free_buckets_without_cost_remain_visible(self):
        stats = opencode_stats(
            {
                "sessions": [
                    _session(
                        "own",
                        NOW - 3600,
                        "/projects/own",
                        [
                            _bucket("opencode", "subscription", input_tokens=4, output_tokens=6),
                            _bucket("opencode", "free", output_tokens=3),
                        ],
                    ),
                ]
            },
            NOW,
        )

        self.assertEqual(set(stats["models"]), {"opencode/subscription", "opencode/free"})
        self.assertEqual(stats["totalTokens"], 13)
        self.assertEqual(stats["totalCostUSD"], 0.0)
        self.assertNotIn("pct", stats)
        self.assertNotIn("pct", stats["models"]["opencode/subscription"])
        self.assertNotIn("pct", stats["models"]["opencode/free"])

    def test_sessions_without_own_buckets_are_unavailable(self):
        stats = opencode_stats(
            {
                "sessions": [
                    _session("upstream", NOW - 3600, "/projects/upstream", [_bucket("openai", "gpt-upstream", output_tokens=42)]),
                ]
            },
            NOW,
        )

        self.assertEqual(stats, {"available": False})

    def test_go_usage_counts_as_opencode_activity(self):
        stats = opencode_stats(
            {"sessions": [_session("go", NOW - 3600, "/projects/go", [_bucket("opencode-go", "kimi", output_tokens=11)])]},
            NOW,
        )

        self.assertEqual(stats["totalSessions"], 1)
        self.assertEqual(stats["totalTokens"], 11)


if __name__ == "__main__":
    unittest.main()
