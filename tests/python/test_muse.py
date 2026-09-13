"""Muse local sessions, catalog/cache invalidation and opt-in quota replay."""

import ast
import inspect
import json
import os
import time
from urllib.error import HTTPError

from _support import FIXTURES, IsolatedHomeTest, raw_fixture
from aiusage import config, envelope
from aiusage.normalize.muse import _compact as muse_compact
from aiusage.normalize.zai import _compact as zai_compact
from aiusage.providers import muse, muse_quota


class MuseTest(IsolatedHomeTest):
    def setUp(self):
        super().setUp()
        self.snapshot = self.home / "muse-sessions/.msp-view-v1/aaa/snapshot-1.json"
        self.write(
            "muse-auth.json",
            {
                "providers": {
                    "meta": {
                        "mechanism": "oauth",
                        "api_key": "muse-secret-token",
                        "access_token": "muse-secret-token",
                        "user_email": "test@example.com",
                        "user_full_name": "Test User",
                    }
                }
            },
        )
        self.write("muse-settings.json", {"schema_version": 1, "provider": "meta", "model": "fixture-spark-9.9"})
        self.write(
            "muse-catalog/6d657461__p746268.json",
            {
                "schema_version": 1,
                "provider_id": "meta",
                "profile_id": "tbh",
                "source": "provider_catalog",
                "rows": [
                    {
                        "model_id": "fixture-spark-9.9",
                        "display_label": "fixture-spark-9.9",
                        "visibility": "visible",
                        "is_current": True,
                        "is_default": True,
                        "context_limit": 1007997,
                        "output_limit": 128000,
                        "cost": {"input": "1.00", "output": "10.00", "cached": "0.10", "currency": "USD"},
                    }
                ],
            },
        )
        events = [
            {
                "payload_type": "runtime.session.metadata",
                "payload": {"kind": "metadata", "record": {"workspace_root": "/home/someone/secret-project"}},
            },
            {
                "payload_type": "run.model.configured",
                "payload": {"kind": "run_model", "record": {"model_id": "fixture-spark-9.9", "provider_id": "meta"}},
            },
        ]
        for event in [
            {"kind": "user_prompt_display"},
            {
                "kind": "model_completed",
                "model": "fixture-spark-9.9",
                "usage": {"input_tokens": 1000, "output_tokens": 200, "cached_tokens": 400, "reasoning_tokens": 10},
            },
            {"kind": "assistant_tool_calls_committed", "tool_calls": [{"name": "bash"}, {"name": "read"}]},
            {"kind": "assistant_message_committed"},
            {"kind": "terminal"},
        ]:
            events.append({"payload_type": "runtime.session", "payload": {"kind": "run", "run_id": "r1", "event": event}})
        self.write_session("aaa", events)
        self.write_session(
            "aaa/subagent/bbb",
            [
                {
                    "payload_type": "runtime.session",
                    "payload": {
                        "kind": "run",
                        "run_id": "r2",
                        "event": {
                            "kind": "model_completed",
                            "model": "fixture-spark-9.9",
                            "usage": {"input_tokens": 500, "output_tokens": 100, "cached_tokens": 0, "reasoning_tokens": 5},
                        },
                    },
                }
            ],
        )
        for variable, path in {
            "MUSE_SESSIONS_DIR": "muse-sessions",
            "MUSE_AUTH_PATH": "muse-auth.json",
            "MUSE_SETTINGS_PATH": "muse-settings.json",
            "MUSE_CATALOG_DIR": "muse-catalog",
        }.items():
            os.environ[variable] = str(self.home / path)

    def write_session(self, directory, events):
        records = [
            dict(event, recorded_at=1785000000000000 + i * 1000000, schema_version=1, stream={"kind": "session", "id": directory.rsplit("/", 1)[-1]})
            for i, event in enumerate(events)
        ]
        self.write(f"muse-sessions/2026/09/04/{directory}/session.jsonl", "".join(json.dumps(record) + "\n" for record in records))

    def provider(self):
        return envelope.build(["muse"])["providers"][0]

    def test_sessions_subagents_prices_and_privacy(self):
        result = self.provider()
        self.assertTrue(result["ok"], result["error"])
        self.assertEqual(result["id"], "muse")
        self.assertTrue(result["details"]["hasLogin"])
        stats = result["details"]["stats"]
        expected = {
            "model": "fixture-spark-9.9",
            "totalOutputTokens": 300,
            "totalTokens": 1800,
            "contextWindow": 1007997,
            "totalSessions": 1,
            "subagentSessions": 1,
            "totalToolCalls": 2,
            "totalMessages": 2,
        }
        for key, value in expected.items():
            with self.subTest(field=key):
                self.assertEqual(stats[key], value)
        self.assertAlmostEqual(stats["totalCostUSD"], 0.00414)
        self.assertEqual(stats["topWorkspaces"][0]["name"], "secret-project")
        self.assertEqual(result["details"]["email"], "test@example.com")
        self.assertEqual(result["historyValues"], {"mu": 1800})
        self.assertEqual([w["key"] for w in result["quotaWindows"]], ["muse_tokens", "muse_spend"])
        self.assertNotRegex(json.dumps(result), "muse-secret-token|/home/someone")

    def test_snapshot_and_catalog_changes_invalidate_cache(self):
        self.provider()  # create a cache from raw sessions
        self.write(
            "muse-sessions/.msp-view-v1/aaa/snapshot-1.json",
            {
                "view_materialization": {
                    "current_state": {"tokenUsage": {"promptTokens": 900, "outputTokens": 250, "totalTokens": 1150}, "turnCount": 1}
                }
            },
        )
        (self.home / "cache/muse-stats.json").unlink(missing_ok=True)
        stats = self.provider()["details"]["stats"]
        self.assertEqual((stats["totalTokens"], stats["totalOutputTokens"]), (1750, 350))
        self.write(
            "muse-sessions/.msp-view-v1/aaa/snapshot-1.json",
            {
                "view_materialization": {
                    "current_state": {"tokenUsage": {"promptTokens": 900, "outputTokens": 450, "totalTokens": 1350}, "turnCount": 1}
                }
            },
        )
        stamp = time.time() + 5
        os.utime(self.snapshot, (stamp, stamp))
        stats = self.provider()["details"]["stats"]
        self.assertEqual((stats["totalTokens"], stats["totalOutputTokens"]), (1950, 550))
        catalog = self.home / "muse-catalog/6d657461__p746268.json"
        catalog.write_text(catalog.read_text(encoding="utf-8").replace('"input": "1.00"', '"input": "2.00"'), encoding="utf-8")
        os.utime(catalog, (stamp + 5, stamp + 5))
        self.assertGreater(self.provider()["details"]["stats"]["totalCostUSD"], 0.005)

    def test_billed_quota_is_opt_in(self):
        result = self.provider()
        self.assertEqual(result["details"]["quotaError"], "disabled")
        self.assertFalse(result["details"]["current"]["available"])
        self.assertNotIn("mc", result["historyValues"])
        self.assertFalse(config.muse_quota_enabled())
        self.assertFalse(config.provider_enabled({}, "muse"))
        os.environ["WIDGET_MUSE_QUOTA"] = "1"
        self.assertTrue(config.muse_quota_enabled())

    def test_recorded_quota_response_and_crlf_sse(self):
        os.environ["WIDGET_MUSE_QUOTA"] = "1"
        os.environ["MUSE_QUOTA_RESPONSE_FILE"] = str(FIXTURES / "muse-quota.json")
        result = self.provider()
        self.assertEqual(result["details"]["quotaError"], "")
        self.assertEqual((result["details"]["current"]["pct"], result["details"]["weekly"]["pct"]), (26, 9))
        sub = raw_fixture("muse-quota")["subscription"]
        event = {"type": "response.subscription_usage", "subscription": sub}
        body = (
            'event: response.created\r\ndata: {"type":"response.created"}\r\n\r\nevent: response.subscription_usage\r\ndata: '
            + json.dumps(event)
            + "\r\n\r\n"
        )
        path = self.home / "quota.sse"
        path.write_bytes(body.encode())  # preserve wire CRLF on Windows too
        os.environ["MUSE_QUOTA_RESPONSE_FILE"] = str(path)
        result = self.provider()
        self.assertEqual(result["details"]["quotaError"], "")
        self.assertEqual(result["historyValues"]["mc"], 26)
        self.assertEqual(result["details"]["weekly"]["pct"], 9)
        self.assertEqual(muse_quota.parse_subscription_event(body), sub)
        self.assertEqual(muse_quota.parse_subscription_event(body.replace("\r\n", "\n")), sub)

    def test_error_classification_and_missing_credential(self):
        for error, expected in (
            (HTTPError("u", 401, "x", {}, None), "rejected"),
            (TimeoutError(), "unreachable"),
            (HTTPError("u", 500, "x", {}, None), "unreachable"),
        ):
            with self.subTest(error=error):
                self.assertEqual(muse_quota.error_code(error), expected)
        os.environ["WIDGET_MUSE_QUOTA"] = "1"
        os.environ["MUSE_AUTH_PATH"] = str(self.home / "missing.json")
        self.assertEqual(muse_quota.get_muse_quota(), ({}, "no-credential"))

    def test_model_and_refresh_price_come_from_cli(self):
        self.assertEqual(muse_quota.quota_model(), "fixture-spark-9.9")
        price = muse_quota.refresh_cost()
        self.assertEqual(price["tokens"], 132)
        self.assertAlmostEqual(price["usd"], 0.001212)

    def test_stats_provider_has_no_network_imports(self):
        network = {"urllib", "http", "socket", "ssl", "requests", "httpx", "asyncio", "ftplib", "smtplib", "telnetlib", "xmlrpc"}
        imports = set()
        for node in ast.walk(ast.parse(inspect.getsource(muse))):
            if isinstance(node, ast.Import):
                imports.update(a.name.split(".")[0] for a in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
                imports.add(node.module.split(".")[0])
        self.assertEqual(imports & network, set())

    def test_shared_formatters_keep_vendor_conventions(self):
        self.assertEqual([zai_compact(n) for n in (41180000, 1000, 500)], ["41.18M", "1.00K", "500"])
        self.assertEqual([muse_compact(n) for n in (30000, 1500, 2000000, 500)], ["30k", "1.5k", "2M", "500"])
