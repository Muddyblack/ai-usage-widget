"""A plan-covered session is priced, but the figure is not money owed."""

import tempfile
import unittest
from unittest import mock

from _support import REPO, seed_session_index  # noqa: F401  (ensures TOOLS is on sys.path)
from aiusage import billing_mode, config, envelope


class BillingModeTest(unittest.TestCase):
    def setUp(self):
        billing_mode.reset_cache()
        self.addCleanup(billing_mode.reset_cache)

    def _claude(self, subscription_type):
        return mock.patch.object(
            billing_mode,
            "get_claude_credentials",
            return_value={"claudeAiOauth": {"subscriptionType": subscription_type}},
        )

    def _openai(self, **fields):
        return mock.patch.object(billing_mode, "get_openai_credentials", return_value=fields)

    def test_a_claude_plan_is_a_subscription_and_a_bare_key_is_metered(self):
        for plan in ("pro", "max", "Max"):
            with self.subTest(plan=plan), self._claude(plan):
                billing_mode.reset_cache()
                self.assertEqual(billing_mode.mode_for("claude"), billing_mode.SUBSCRIPTION)
        for plan in ("", "api", None):
            with self.subTest(plan=plan), self._claude(plan):
                billing_mode.reset_cache()
                self.assertEqual(billing_mode.mode_for("claude"), billing_mode.API)

    def test_a_chatgpt_login_is_a_plan_even_without_a_plan_name(self):
        with self._openai(authMode="chatgpt", planType=""):
            self.assertEqual(billing_mode.mode_for("openai"), billing_mode.SUBSCRIPTION)

    def test_an_openai_api_key_alone_is_metered(self):
        with self._openai(authMode="apikey", planType="", openaiApiKey="sk-x"):
            self.assertEqual(billing_mode.mode_for("openai"), billing_mode.API)

    def test_a_provider_with_no_plan_signal_is_metered(self):
        self.assertEqual(billing_mode.mode_for("cline"), billing_mode.API)
        self.assertEqual(billing_mode.mode_for("opencode"), billing_mode.API)

    def test_an_unreadable_credential_store_falls_back_to_metered(self):
        """Never hide a cost the user might actually owe."""
        with mock.patch.object(billing_mode, "get_claude_credentials", side_effect=OSError("locked")):
            self.assertEqual(billing_mode.mode_for("claude"), billing_mode.API)

    def test_the_lookup_is_memoized_per_process(self):
        with self._claude("pro") as credentials:
            billing_mode.mode_for("claude")
            billing_mode.mode_for("claude")
        self.assertEqual(credentials.call_count, 1)


class LocalSpendSplitTest(unittest.TestCase):
    def _row(self, provider, cost, billing):
        return {
            "provider": provider,
            "source": provider,
            "costUSD": cost,
            "costStatus": "exact",
            "costProvenance": "estimated",
            "costBilling": billing,
        }

    def _spend(self, rows):
        with tempfile.TemporaryDirectory() as directory:
            seed_session_index(directory, rows)
            with mock.patch.object(config, "cache_dir", return_value=directory):
                return envelope._local_spend()

    def test_plan_usage_never_lands_in_the_metered_total(self):
        spend = self._spend(
            [
                self._row("claude", 100.0, "subscription"),
                self._row("cline", 2.0, "api"),
            ]
        )

        self.assertEqual(spend["estimated"]["totalUSD"], 2.0)
        self.assertEqual(list(spend["estimated"]["providers"]), ["cline::cline"])
        self.assertEqual(spend["subscription"]["totalUSD"], 100.0)
        self.assertEqual(list(spend["subscription"]["providers"]), ["claude::claude"])

    def test_a_row_without_a_billing_mode_counts_as_metered(self):
        row = self._row("cline", 3.0, "api")
        del row["costBilling"]

        self.assertEqual(self._spend([row])["estimated"]["totalUSD"], 3.0)

    def test_only_plan_rows_leave_the_metered_total_empty(self):
        spend = self._spend([self._row("openai", 7.5, "subscription")])

        self.assertEqual(spend["estimated"]["costStatus"], "unavailable")
        self.assertEqual(spend["subscription"]["totalUSD"], 7.5)


if __name__ == "__main__":
    unittest.main()


class GrokSummaryLayoutTest(unittest.TestCase):
    """Grok moved from one signals.json per session to a per-session directory
    with summary.json + updates.jsonl; the old reader found nothing."""

    def _session(self, root, workspace, session_id, title, usage):
        import json
        import os

        directory = os.path.join(root, "sessions", workspace, session_id)
        os.makedirs(directory)
        with open(os.path.join(directory, "summary.json"), "w", encoding="utf-8") as stream:
            json.dump(
                {
                    "info": {"id": session_id, "cwd": "/mnt/projects/demo"},
                    "generated_title": title,
                    "current_model_id": "grok-4.6",
                    "last_active_at": "2026-09-16T10:33:33Z",
                },
                stream,
            )
        with open(os.path.join(directory, "updates.jsonl"), "w", encoding="utf-8") as stream:
            for totals in usage:
                stream.write(json.dumps({"method": "x", "params": {"update": {"usage": totals}}}) + "\n")
        return directory

    def test_reads_the_title_and_the_last_cumulative_usage_record(self):
        import tempfile

        from aiusage import sessions

        with tempfile.TemporaryDirectory() as root:
            self._session(
                root,
                "%2Fmnt%2Fprojects%2Fdemo",
                "01a0a9c3-d242-7842-b339-601736230170",
                "Audio viz features",
                [
                    {"inputTokens": 10, "outputTokens": 1},
                    # cumulative — the last record wins, it is not a sum
                    {"inputTokens": 1000, "outputTokens": 20, "cachedReadTokens": 500},
                ],
            )
            with mock.patch.object(sessions, "grok_home", return_value=root):
                rows = sessions._grok_entries(include_all=True)

        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["title"], "Audio viz features")
        self.assertEqual(rows[0]["provider"], "grok")
        self.assertIn("1.5K tok", rows[0]["detail"])
        self.assertIn("grok-4.6", rows[0]["detail"])

    def test_a_session_without_updates_still_lists(self):
        import os
        import tempfile

        from aiusage import sessions

        with tempfile.TemporaryDirectory() as root:
            directory = self._session(root, "%2Fw", "01a0a9c3-d242-7842-b339-601736230171", "No usage yet", [])
            os.remove(os.path.join(directory, "updates.jsonl"))
            with mock.patch.object(sessions, "grok_home", return_value=root):
                rows = sessions._grok_entries(include_all=True)

        self.assertEqual([row["title"] for row in rows], ["No usage yet"])
        self.assertEqual(rows[0].get("costStatus"), "unavailable")
