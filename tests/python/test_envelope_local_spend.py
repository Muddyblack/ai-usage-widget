import math
import unittest
from unittest import mock

import _support  # noqa: F401 — puts the backend package on sys.path
from aiusage import envelope


class LocalSpendEnvelopeTest(unittest.TestCase):
    def build(self, sessions):
        provider = {
            "id": "claude",
            "ok": True,
            "details": {"stats": {"totalCostUSD": 99.0}},
        }
        with (
            mock.patch.object(envelope, "collect", return_value={}),
            mock.patch.object(envelope, "normalize", return_value=provider),
            mock.patch("aiusage.sessions.collect_sessions", return_value={"sessions": sessions}),
        ):
            return envelope.build(["claude"], now=1_700_000_000)

    def test_no_sessions_is_unavailable_and_omits_empty_totals(self):
        result = self.build([])

        self.assertEqual(
            result["localSpend"],
            {"actual": {"costStatus": "unavailable"}, "estimated": {"costStatus": "unavailable"}},
        )

    def test_exact_session_has_total_and_provider_rollup(self):
        result = self.build(
            [
                {
                    "provider": "opencode",
                    "costUSD": 0.42,
                    "costStatus": "exact",
                    "costProvenance": "actual",
                    "sessionId": "private-session-id",
                    "title": "private title",
                    "path": "/private/path",
                    "prompt": "private prompt",
                }
            ]
        )

        self.assertEqual(
            result["localSpend"],
            {
                "actual": {
                    "totalUSD": 0.42,
                    "costStatus": "exact",
                    "costProvenance": "actual",
                    "providers": {"opencode": {"costUSD": 0.42, "costStatus": "exact", "costProvenance": "actual"}},
                },
                "estimated": {"costStatus": "unavailable"},
            },
        )

    def test_opencode_rollups_are_separate_by_trusted_upstream_provider(self):
        result = self.build(
            [
                {
                    "provider": "anthropic",
                    "source": "opencode",
                    "billingProvider": "anthropic",
                    "costUSD": 0.42,
                    "costStatus": "exact",
                    "costProvenance": "estimated",
                },
                {
                    "provider": "openai",
                    "source": "opencode",
                    "billingProvider": "openai",
                    "costUSD": 0.13,
                    "costStatus": "exact",
                    "costProvenance": "actual",
                },
            ]
        )

        self.assertEqual(
            result["localSpend"]["estimated"]["providers"],
            {
                "anthropic::opencode": {
                    "costUSD": 0.42,
                    "costStatus": "exact",
                    "costProvenance": "estimated",
                    "source": "opencode",
                }
            },
        )
        self.assertEqual(
            result["localSpend"]["actual"]["providers"],
            {
                "openai::opencode": {
                    "costUSD": 0.13,
                    "costStatus": "exact",
                    "costProvenance": "actual",
                    "source": "opencode",
                }
            },
        )

    def test_native_and_opencode_same_provider_keep_distinct_rollups(self):
        result = self.build(
            [
                {
                    "provider": "anthropic",
                    "costUSD": 0.21,
                    "costStatus": "exact",
                    "costProvenance": "estimated",
                },
                {
                    "provider": "anthropic",
                    "source": "opencode",
                    "billingProvider": "anthropic",
                    "costUSD": 0.42,
                    "costStatus": "exact",
                    "costProvenance": "estimated",
                },
            ]
        )

        self.assertEqual(
            result["localSpend"]["estimated"]["providers"],
            {
                "anthropic": {
                    "costUSD": 0.21,
                    "costStatus": "exact",
                    "costProvenance": "estimated",
                },
                "anthropic::opencode": {
                    "costUSD": 0.42,
                    "costStatus": "exact",
                    "costProvenance": "estimated",
                    "source": "opencode",
                },
            },
        )

    def test_multi_provider_opencode_session_rolls_up_per_provider(self):
        result = self.build(
            [
                {
                    "provider": "opencode",
                    "source": "opencode",
                    "costUSD": 0.55,
                    "costStatus": "exact",
                    "costProvenance": "actual",
                    "providerCosts": {
                        "ollama-cloud": {"costUSD": 0.42, "costStatus": "exact", "costProvenance": "actual"},
                        "openai": {"costUSD": 0.13, "costStatus": "exact", "costProvenance": "actual"},
                    },
                }
            ]
        )

        self.assertEqual(result["localSpend"]["actual"]["totalUSD"], 0.55)
        self.assertEqual(
            result["localSpend"]["actual"]["providers"],
            {
                "ollama-cloud::opencode": {
                    "costUSD": 0.42,
                    "costStatus": "exact",
                    "costProvenance": "actual",
                    "source": "opencode",
                },
                "openai::opencode": {
                    "costUSD": 0.13,
                    "costStatus": "exact",
                    "costProvenance": "actual",
                    "source": "opencode",
                },
            },
        )

    def test_multi_provider_opencode_mixed_provider_costs_split_by_origin(self):
        result = self.build(
            [
                {
                    "provider": "opencode",
                    "source": "opencode",
                    "costUSD": 0.62,
                    "costStatus": "exact",
                    "costProvenance": "mixed",
                    "costBreakdown": {"actualUSD": 0.42, "estimatedUSD": 0.2},
                    "providerCosts": {
                        "ollama-cloud": {
                            "costUSD": 0.62,
                            "costStatus": "exact",
                            "costProvenance": "mixed",
                            "costBreakdown": {"actualUSD": 0.42, "estimatedUSD": 0.2},
                        }
                    },
                }
            ]
        )

        self.assertEqual(result["localSpend"]["actual"]["providers"]["ollama-cloud::opencode"]["costUSD"], 0.42)
        self.assertEqual(result["localSpend"]["estimated"]["providers"]["ollama-cloud::opencode"]["costUSD"], 0.2)

    def test_exact_and_partial_sessions_sum_with_partial_status(self):
        result = self.build(
            [
                {"provider": "opencode", "costUSD": 0.42, "costStatus": "exact", "costProvenance": "actual"},
                {"provider": "cline", "costUSD": 0.13, "costStatus": "partial", "costProvenance": "actual"},
                {"provider": "cline", "costUSD": 0.07, "costStatus": "exact", "costProvenance": "actual"},
            ]
        )

        self.assertEqual(
            result["localSpend"],
            {
                "actual": {
                    "totalUSD": 0.42,
                    "costStatus": "exact",
                    "costProvenance": "actual",
                    "providers": {"opencode": {"costUSD": 0.42, "costStatus": "exact", "costProvenance": "actual"}},
                },
                "estimated": {"costStatus": "unavailable"},
            },
        )

    def test_actual_and_estimated_totals_are_separate(self):
        result = self.build(
            [
                {"provider": "opencode", "costUSD": 0.42, "costStatus": "exact", "costProvenance": "actual"},
                {"provider": "claude", "costUSD": 0.13, "costStatus": "partial", "costProvenance": "estimated"},
                {"provider": "claude", "costUSD": 0.07, "costStatus": "exact", "costProvenance": "estimated"},
            ]
        )

        self.assertEqual(
            result["localSpend"],
            {
                "actual": {
                    "totalUSD": 0.42,
                    "costStatus": "exact",
                    "costProvenance": "actual",
                    "providers": {"opencode": {"costUSD": 0.42, "costStatus": "exact", "costProvenance": "actual"}},
                },
                "estimated": {
                    "totalUSD": 0.2,
                    "costStatus": "partial",
                    "costProvenance": "estimated",
                    "providers": {"claude": {"costUSD": 0.2, "costStatus": "partial", "costProvenance": "estimated"}},
                },
            },
        )
        self.assertNotIn("totalUSD", result["localSpend"])

    def test_mixed_session_contributes_each_origin_subtotal(self):
        result = self.build(
            [
                {
                    "provider": "opencode",
                    "costUSD": 0.62,
                    "costStatus": "exact",
                    "costProvenance": "mixed",
                    "costBreakdown": {"actualUSD": 0.42, "estimatedUSD": 0.2},
                    "sessionId": "private-session-id",
                }
            ]
        )

        self.assertEqual(result["localSpend"]["actual"]["totalUSD"], 0.42)
        self.assertEqual(result["localSpend"]["actual"]["costStatus"], "exact")
        self.assertEqual(result["localSpend"]["estimated"]["totalUSD"], 0.2)
        self.assertEqual(result["localSpend"]["estimated"]["costStatus"], "exact")

    def test_mixed_partial_session_marks_both_origin_totals_partial(self):
        result = self.build(
            [
                {
                    "provider": "cline",
                    "costUSD": 0.62,
                    "costStatus": "partial",
                    "costProvenance": "mixed",
                    "costBreakdown": {"actualUSD": 0.42, "estimatedUSD": 0.2},
                }
            ]
        )

        self.assertEqual(result["localSpend"]["actual"], {"costStatus": "unavailable"})
        self.assertEqual(result["localSpend"]["estimated"]["totalUSD"], 0.2)
        self.assertEqual(result["localSpend"]["estimated"]["costStatus"], "partial")

    def test_mixed_rows_without_contributors_are_unavailable(self):
        result = self.build(
            [
                {
                    "provider": "cline",
                    "costUSD": 0.62,
                    "costStatus": "exact",
                    "costProvenance": "mixed",
                }
            ]
        )

        self.assertEqual(result["localSpend"]["actual"], {"costStatus": "unavailable"})
        self.assertEqual(result["localSpend"]["estimated"], {"costStatus": "unavailable"})

    def test_mixed_rows_reject_malformed_subtotals(self):
        for breakdown in (
            {"actualUSD": math.nan, "estimatedUSD": 0.2},
            {"actualUSD": 0.42, "estimatedUSD": math.inf},
            {"actualUSD": "0.42", "estimatedUSD": 0.2},
        ):
            with self.subTest(breakdown=breakdown):
                result = self.build(
                    [
                        {
                            "provider": "cline",
                            "costUSD": 0.62,
                            "costStatus": "exact",
                            "costProvenance": "mixed",
                            "costBreakdown": breakdown,
                        }
                    ]
                )

                self.assertEqual(result["localSpend"]["actual"], {"costStatus": "unavailable"})
                self.assertEqual(result["localSpend"]["estimated"], {"costStatus": "unavailable"})

    def test_mixed_rows_reject_subtotals_that_do_not_match_session_cost(self):
        result = self.build(
            [
                {
                    "provider": "opencode",
                    "costUSD": 0.62,
                    "costStatus": "exact",
                    "costProvenance": "mixed",
                    "costBreakdown": {"actualUSD": 0.42, "estimatedUSD": 0.1},
                }
            ]
        )

        self.assertEqual(result["localSpend"]["actual"], {"costStatus": "unavailable"})
        self.assertEqual(result["localSpend"]["estimated"], {"costStatus": "unavailable"})

    def test_mixed_rows_preserve_zero_component_when_parent_cost_matches(self):
        result = self.build(
            [
                {
                    "provider": "opencode",
                    "costUSD": 0.2,
                    "costStatus": "exact",
                    "costProvenance": "mixed",
                    "costBreakdown": {"actualUSD": 0, "estimatedUSD": 0.2},
                }
            ]
        )

        self.assertEqual(result["localSpend"]["actual"]["totalUSD"], 0)
        self.assertEqual(result["localSpend"]["actual"]["providers"]["opencode"]["costUSD"], 0)
        self.assertEqual(result["localSpend"]["estimated"]["totalUSD"], 0.2)

    def test_mixed_rows_allow_small_decimal_rounding_error(self):
        result = self.build(
            [
                {
                    "provider": "opencode",
                    "costUSD": 0.6200000000005,
                    "costStatus": "exact",
                    "costProvenance": "mixed",
                    "costBreakdown": {"actualUSD": 0.42, "estimatedUSD": 0.2},
                }
            ]
        )

        self.assertEqual(result["localSpend"]["actual"]["totalUSD"], 0.42)
        self.assertEqual(result["localSpend"]["estimated"]["totalUSD"], 0.2)

    def test_unavailable_actual_and_estimated_totals_have_no_numeric_fields(self):
        result = self.build(
            [
                {"provider": "claude", "costUSD": 0.5, "costStatus": "exact", "costProvenance": "unknown"},
                {"provider": "claude", "costUSD": math.nan, "costStatus": "partial", "costProvenance": "estimated"},
            ]
        )

        self.assertEqual(
            result["localSpend"],
            {"actual": {"costStatus": "unavailable"}, "estimated": {"costStatus": "unavailable"}},
        )

    def test_invalid_costs_never_contribute(self):
        invalid = [
            {"provider": "claude", "costStatus": "exact", "costUSD": 0},
            {"provider": "claude", "costStatus": "partial", "costUSD": -0.1},
            {"provider": "claude", "costStatus": "exact", "costUSD": math.nan},
            {"provider": "claude", "costStatus": "exact", "costUSD": math.inf},
            {"provider": "claude", "costStatus": "exact", "costUSD": -math.inf},
            {"provider": "claude", "costStatus": "exact"},
            {"provider": "claude", "costStatus": "unavailable", "costUSD": 0.9},
        ]

        result = self.build(invalid)

        self.assertEqual(
            result["localSpend"],
            {"actual": {"costStatus": "unavailable"}, "estimated": {"costStatus": "unavailable"}},
        )

    def test_collection_failure_does_not_fail_envelope(self):
        provider = {"id": "claude", "ok": True}
        with (
            mock.patch.object(envelope, "collect", return_value={}),
            mock.patch.object(envelope, "normalize", return_value=provider),
            mock.patch("aiusage.sessions.collect_sessions", side_effect=RuntimeError("broken store")),
        ):
            result = envelope.build(["claude"], now=1_700_000_000)

        self.assertEqual(
            result["localSpend"],
            {"actual": {"costStatus": "unavailable"}, "estimated": {"costStatus": "unavailable"}},
        )
        self.assertEqual(result["providers"], [provider])

    def test_existing_envelope_keys_and_provider_spend_are_unchanged(self):
        result = self.build([])

        self.assertEqual(
            set(result),
            {"schemaVersion", "updatedAt", "active", "providers", "localSpend"},
        )
        self.assertEqual(result["schemaVersion"], 1)
        self.assertEqual(result["updatedAt"], 1_700_000_000)
        self.assertEqual(result["active"], "claude")
        self.assertEqual(result["providers"][0]["details"]["stats"]["totalCostUSD"], 99.0)


if __name__ == "__main__":
    unittest.main()
