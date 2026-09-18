import contextlib
import io
import json
import os
import unittest
from unittest import mock

from _support import IsolatedHomeTest, raw_fixture
from aiusage import __main__ as backend
from aiusage import billing, config, pricing, sessions
from aiusage.http import HttpResult


def _catalog():
    return {
        "claude-test": {
            "litellm_provider": "anthropic",
            "mode": "chat",
            "input_cost_per_token": 0.000002,
            "output_cost_per_token": 0.000008,
        },
        "gpt-test": {
            "litellm_provider": "openai",
            "mode": "responses",
            "input_cost_per_token": 0.000004,
            "output_cost_per_token": 0.000012,
        },
    }


class PricingRefreshCommandTest(IsolatedHomeTest):
    def _run_backend(self, *args):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = backend.main(list(args))
        return code, json.loads(output.getvalue())

    def test_help_discovers_one_pricing_refresh_operation(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = backend.main(["--help"])

        self.assertEqual(code, 0)
        self.assertIn("--refresh-pricing", output.getvalue())

    def test_forced_refresh_returns_one_success_envelope_and_one_fetch(self):
        with (
            mock.patch.object(pricing.time, "time", return_value=1_800_000_000),
            mock.patch.object(
                pricing,
                "fetch_json",
                return_value=HttpResult(200, json.dumps(_catalog())),
            ) as fetch,
        ):
            code, result = self._run_backend("--refresh-pricing")

        self.assertEqual(code, 0)
        self.assertEqual(result, {"ok": True, "status": "refreshed", "fetchedAt": 1_800_000_000, "error": ""})
        fetch.assert_called_once_with(pricing.SOURCE_URL, timeout=10)

    def test_failed_refresh_keeps_rates_and_reports_stale_good(self):
        fetched_at = 1_799_000_000
        self.write(
            "cache/pricing-litellm-v1.json",
            {
                "version": 1,
                "source": pricing.SOURCE_URL,
                "fetchedAt": fetched_at,
                "checkedAt": fetched_at,
                "providers": {
                    "anthropic": {"claude-test": {"input": 2, "output": 8}},
                    "openai": {"gpt-test": {"input": 4, "output": 12}},
                },
                "error": "",
            },
        )
        with (
            mock.patch.object(pricing.time, "time", return_value=fetched_at + pricing.REFRESH_SECONDS),
            mock.patch.object(pricing, "fetch_json", return_value=HttpResult(503, "")) as fetch,
        ):
            code, result = self._run_backend("--refresh-pricing")

        self.assertEqual(code, 0)
        self.assertTrue(result["ok"])
        self.assertEqual(result["status"], "stale-good")
        self.assertEqual(result["fetchedAt"], fetched_at)
        self.assertIn("pricing download failed", result["error"])
        fetch.assert_called_once_with(pricing.SOURCE_URL, timeout=10)

    def test_failed_refresh_without_cache_is_actionable_and_nonzero(self):
        with mock.patch.object(pricing, "fetch_json", return_value=HttpResult(503, "")) as fetch:
            code, result = self._run_backend("--refresh-pricing")

        self.assertEqual(code, 1)
        self.assertEqual(result["ok"], False)
        self.assertEqual(result["status"], "no-cache")
        self.assertEqual(result["fetchedAt"], 0)
        self.assertIn("no usable pricing rates", result["error"])
        fetch.assert_called_once_with(pricing.SOURCE_URL, timeout=10)

    def test_following_all_reuses_the_refreshed_cache_without_pricing_fetch(self):
        providers = dict.fromkeys(config.ALL_PROVIDERS, False)
        providers["claude"] = True
        self.write("config.json", {"providers": providers})
        org_usage = self.write("claude-org.json", {"data": [{"model": "claude-test", "input_tokens": 10, "output_tokens": 5}]})
        os.environ["WIDGET_CLAUDE_ADMIN_KEY"] = "test-key"
        os.environ["CLAUDE_ORG_USAGE_RESPONSE_FILE"] = str(org_usage)
        with (
            mock.patch.object(pricing.time, "time", return_value=1_800_000_000),
            mock.patch.object(
                pricing,
                "fetch_json",
                return_value=HttpResult(200, json.dumps(_catalog())),
            ) as fetch,
            mock.patch("aiusage.collect.provider_status", return_value=None),
        ):
            self.assertEqual(self._run_backend("--refresh-pricing")[0], 0)
            fetch.reset_mock()
            code, result = self._run_backend("--all")

        self.assertEqual(code, 0)
        self.assertEqual(result["providers"][0]["id"], "claude")
        fetch.assert_not_called()


class SessionCostContractTest(IsolatedHomeTest):
    def test_exact_multi_model_cost_is_structured_without_singular_model(self):
        with mock.patch.object(
            pricing,
            "cached_catalog",
            return_value={
                "anthropic": {
                    "claude-a": {"input": 2, "output": 8},
                    "claude-b": {"input": 4, "output": 10},
                }
            },
        ):
            entry = sessions._with_usage_cost(
                sessions._entry("claude", "Title", 2_000, detail="1.0K tok"),
                "anthropic",
                [
                    billing.UsageBucket("anthropic", "claude-a", "session", 100, 50),
                    billing.UsageBucket("anthropic", "claude-b", "session", 200, 25),
                ],
            )

        self.assertEqual(entry["costStatus"], "exact")
        self.assertAlmostEqual(entry["costUSD"], 0.00165)
        self.assertNotIn("model", entry)
        self.assertEqual(entry["detail"], "1.0K tok")

    def test_unknown_model_is_partial_and_missing_usage_is_unavailable(self):
        with mock.patch.object(
            pricing,
            "cached_catalog",
            return_value={"anthropic": {"known": {"input": 2, "output": 8}}},
        ):
            partial = sessions._with_usage_cost(
                sessions._entry("claude", "Partial", 2_000),
                "anthropic",
                [
                    billing.UsageBucket("anthropic", "known", "partial", 100, 50),
                    billing.UsageBucket("anthropic", "unknown", "partial", 100, 50),
                ],
            )
            unavailable = sessions._with_usage_cost(
                sessions._entry("claude", "Unavailable", 2_000),
                "anthropic",
                [],
            )

        self.assertEqual(partial["costStatus"], "partial")
        self.assertIn("costUSD", partial)
        self.assertEqual(unavailable["costStatus"], "unavailable")
        self.assertNotIn("costUSD", unavailable)

    def test_openrouter_fallback_reloads_from_disk_without_another_fetch(self):
        fetch = mock.Mock(
            side_effect=[
                HttpResult(503, ""),
                HttpResult(200, json.dumps(raw_fixture("pricing-openrouter-response"))),
            ]
        )
        with mock.patch.object(pricing, "fetch_json", fetch):
            pricing.load_catalog(models={"anthropic": ["claude-missing"]})
            pricing._CURRENT_SNAPSHOTS.clear()
            pricing._REFRESH_GENERATIONS.clear()

            result = pricing.load_catalog(models={"anthropic": ["claude-missing"]})

        self.assertEqual(result["providers"]["anthropic"]["claude-missing"]["input"], 3.0)
        self.assertEqual(result["providers"]["anthropic"]["claude-missing"]["output"], 9.0)
        self.assertEqual(fetch.call_count, 2)


if __name__ == "__main__":
    unittest.main()
