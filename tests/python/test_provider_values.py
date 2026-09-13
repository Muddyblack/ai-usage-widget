"""Provider-specific expectations from the original shell contract suite.

Paths select a single JSON field; expected values are deliberately small so a
failure identifies the calculation that changed instead of diffing a snapshot.
"""

import unittest

from _support import fixture


class ProviderValuesTest(unittest.TestCase):
    def check_fields(self, name, fields):
        result = fixture(name)
        for path, expected in fields.items():
            with self.subTest(fixture=name, field=path):
                value = result
                for part in path.split("/"):
                    value = value[int(part)] if isinstance(value, list) else value[part]
                if isinstance(expected, float):
                    self.assertAlmostEqual(value, expected, places=6)
                else:
                    self.assertEqual(value, expected)

    def test_claude(self):
        self.check_fields(
            "claude-success",
            {
                "details/session/tokensUsed": 120000,
                "details/session/tokenLimit": 500000,
                "quotaWindows/0/key": "session",
                "quotaWindows/0/available": True,
                "quotaWindows/0/detail": "120000 / 500000 tokens",
                "details/scopedWeekly/0/pct": 44,
                "details/scopedWeekly/0/model": "",
                "details/scopedWeekly/0/label": "7-day scoped",
                "details/hasOAuth": True,
                "details/hasAdminKey": True,
                "details/subscriptionType": "max",
                "details/organizationUuid": "org-1234",
                "details/organizationUsage/totalInputTokens": 2005000,
                "details/organizationUsage/totalOutputTokens": 400500,
                "details/organizationUsage/models/claude-sonnet-4/priced": True,
                "details/organizationUsage/models/mystery-model/priced": False,
                "details/organizationUsage/totalCostUSD": 12.0,
                "details/stats/available": True,
                "details/stats/activeDays": 3,
                "details/stats/longestStreak": 3,
                "details/stats/totalToolCalls": 13,
                "details/stats/totalTokens": 165,
                "details/stats/favoriteModel": "claude-opus-4",
                "details/stats/peakHour": 14,
                "details/stats/dailyTokens/0/date": "2026-07-22",
                "details/stats/dailyTokens/1/date": "2026-07-23",
                "details/stats/dailyTokens/1/total": 120,
                "chartWindows/0/granularity": "5h",
                "chartWindows/0/periodMs": 18000000,
                "chartWindows/0/resetAt": 1784473200,
                "chartWindows/1/size": 86400000,
                "chartWindows/1/periodMs": 18000000,
                "chartWindows/2/size": 604800000,
                "chartWindows/2/periodMs": 604800000,
                "chartWindows/2/resetAt": 1784991600,
                "chartWindows/3/size": 2592000000,
                "chartWindows/3/granularity": "30d",
                "details/status/indicator": "minor",
                "details/status/incidents": ["Elevated errors"],
                "details/status/latestUpdate": "We are looking into it.",
                "details/status/url": "https://status.claude.com",
            },
        )
        self.check_fields(
            "claude-scoped-week",
            {
                "ok": True,
                "details/session/pct": 9,
                "details/weekly/pct": 17,
                "details/scopedWeekly/0/pct": 13,
                "details/scopedWeekly/0/model": "Fable",
                "details/scopedWeekly/0/key": "weekly_fable",
                "details/scopedWeekly/0/label": "7-day Fable",
                "details/scopedWeekly/0/resetAt": 1786949999,
                "quotaWindows/2/available": True,
                "quotaWindows/2/pct": 13,
                "quotaWindows/2/label": "7-day Fable",
            },
        )
        self.check_fields(
            "claude-malformed",
            {"ok": True, "details/session/available": False, "details/weekly/available": False, "historyValues": {}, "chartWindows": []},
        )
        self.check_fields("claude-admin-key-only", {"ok": True, "error": "OAuth missing — API stats only", "details/hasAdminKey": True})

    def test_codex(self):
        self.check_fields(
            "openai-codex-success",
            {
                "details/codex/available": True,
                "details/codex/session/pct": 58,
                "details/codex/session/resetAt": 1785010000,
                "details/codex/weekly/pct": 30,
                "details/codex/additional/0/name": "Spark",
                "details/codex/additional/0/limitReached": True,
                "details/codex/additional/0/session/pct": 90,
                "details/codex/additional/0/weekly/pct": 9,
                "details/organizationUsage/totalInputTokens": 3001000,
                "details/organizationUsage/models/gpt-4o/priced": True,
                "details/stats/available": True,
                "details/stats/model": "gpt-5-codex",
                "details/stats/effortLevel": "medium",
                "details/stats/activeDays": 2,
                "details/stats/dailyTokens/0/date": "2026-07-23",
                "details/stats/dailyTokens/1/date": "2026-07-24",
            },
        )
        self.check_fields("openai-legacy-windows", {"details/codex/additional/0/session/pct": 100})
        self.check_fields(
            "openai-api-key-only", {"ok": True, "error": "", "chartWindows": [], "details/codex/available": False, "summary/hasChart": False}
        )
        self.assertGreater(fixture("openai-api-key-only")["details"]["organizationUsage"]["totalCostUSD"], 0)
        self.check_fields("openai-offline", {"ok": True, "stale": True, "details/codex/available": False})

    def test_antigravity_and_kiro(self):
        self.check_fields(
            "antigravity-success",
            {
                "details/googlePct": 40,
                "details/externalPct": 100,
                "details/pct": 60,
                "details/groups/0/key": "gemini",
                "details/groups/1/models": ["autocomplete-1", "claude-sonnet-4-5"],
                "details/groups/1/isExhausted": True,
                "details/models/autocomplete-1/hasQuota": False,
                "details/models/gemini-3-pro/usedPct": 60,
            },
        )
        self.check_fields(
            "kiro-success",
            {"details/pct": 25, "details/currentUsage": 250, "details/overageCharges": 0.8, "details/resetAt": 1785542400, "details/source": "ide"},
        )
        self.check_fields(
            "kiro-cli-success",
            {
                "ok": True,
                "details/source": "cli",
                "details/planType": "free",
                "details/currentUsage": 0.13,
                "details/usageLimit": 50,
                "details/resetAt": 1790812800,
                "quotaWindows/0/detail": "0.13 / 50 credits",
            },
        )

    def test_money_providers(self):
        self.check_fields(
            "mistral-success", {"details/vibe/totalCost": 12.5, "details/vibe/sessionCount": 4, "details/keyValid": True, "details/hasKey": True}
        )
        self.assertEqual(len(fixture("mistral-success")["details"]["availableModels"]), 2)
        self.check_fields("mistral-invalid-key", {"details/vibe/totalCost": 12.5})
        self.check_fields("openrouter-success", {"details/usageUSD": 3.25, "details/limitUSD": 10, "quotaWindows/0/detail": "$3.25 / $10"})
        self.check_fields("openrouter-unlimited", {"ok": True, "details/limitUSD": None, "summary/pct": 0, "historyValues": {}})
        self.assertTrue(fixture("openrouter-unlimited")["quotaWindows"][0]["detail"].endswith("unlimited"))
        self.check_fields(
            "deepseek-success", {"details/primaryTotal": 12.5, "details/symbol": "$", "summary/text": "$12.5", "quotaWindows/1/detail": "$2.5 / $10"}
        )
        self.check_fields(
            "kimi-success",
            {
                "details/keyValid": True,
                "details/availableBalance": 49.58894,
                "details/voucherBalance": 46.58893,
                "details/cashBalance": 3.00001,
                "summary/detail": "Moonshot API",
                "details/codePlan/available": False,
            },
        )

    def test_grok(self):
        self.check_fields(
            "grok-billing",
            {
                "details/hasBilling": True,
                "details/pct": 42,
                "summary/hasChart": True,
                "quotaWindows/0/detail": "21 / 50",
                "quotaWindows/1/detail": "1 session · 900 tokens · 4 tool calls",
            },
        )
        self.assertEqual(len(fixture("grok-billing")["quotaWindows"]), 2)
        self.check_fields(
            "grok-free-tier",
            {
                "ok": True,
                "details/hasBilling": False,
                "summary/text": "CLI",
                "summary/hasChart": False,
                "historyValues": {},
                "chartWindows": [],
                "quotaWindows/1/detail": "3 sessions · 12000 tokens · 9 tool calls",
            },
        )

    def test_zai(self):
        self.check_fields(
            "zai-success",
            {
                "details/hasKey": True,
                "details/token/pct": 25,
                "details/token/resetAt": 1785003600,
                "details/tools/resetAt": 1785007200,
                "details/tools/remaining": 60,
                "quotaWindows/0/detail": "250 / 1000 tokens",
                "details/today/available": False,
            },
        )
        self.assertNotIn("zai_today", [w["key"] for w in fixture("zai-success")["quotaWindows"]])
        self.check_fields("zai-absolute-reset", {"ok": True, "details/tools/resetAt": 1786000000})
        self.assertEqual(next(w["resetAt"] for w in fixture("zai-absolute-reset")["quotaWindows"] if w["key"] == "zai_tokens_long"), 1785086400)
        self.check_fields(
            "zai-today",
            {
                "ok": True,
                "details/today/available": True,
                "details/today/tokens": 41175632,
                "details/today/calls": 370,
                "details/today/date": "2026-08-11",
                "quotaWindows/3/resetAt": 1786485600,
            },
        )
        self.assertEqual([m["name"] for m in fixture("zai-today")["details"]["today"]["models"]], ["GLM-5.2", "GLM-5-Turbo", "GLM-4.7"])

    def test_copilot(self):
        self.check_fields(
            "copilot-success",
            {
                "details/hasKey": True,
                "details/used": 125,
                "details/quota": 500,
                "details/pct": 25,
                "details/resetAt": 1785542400,
                "quotaWindows/0/detail": "125 / 500 requests",
            },
        )
        self.check_fields(
            "copilot-plan-quota",
            {
                "ok": True,
                "details/quota": 200,
                "details/used": 19.8,
                "details/plan": "individual",
                "quotaWindows/0/detail": "19.8 / 200 requests",
                "quotaWindows/0/resetAt": 1785542400,
                "details/stats/available": True,
                "details/stats/totalSessions": 12,
                "details/stats/totalMessages": 96,
                "details/stats/totalToolCalls": 210,
                "details/stats/totalFiles": 34,
                "details/stats/totalRepositories": 2,
                "details/stats/activeDays": 3,
                "details/stats/longestStreak": 3,
                "details/stats/peakHour": 14,
                "details/stats/totalTokens": 0,
                "details/stats/dailyUnit": "messages",
                "details/stats/topRepositories/0/name": "octocat/hello",
            },
        )
        self.assertEqual([d["total"] for d in fixture("copilot-plan-quota")["details"]["stats"]["dailySeries"]], [20, 36, 40])
        self.check_fields(
            "copilot-unlimited",
            {
                "ok": True,
                "details/unlimited": True,
                "summary/text": "∞",
                "quotaWindows/0/showMeter": False,
                "quotaWindows/0/detail": "412 requests · unlimited",
            },
        )
        self.check_fields("copilot-missing", {"details/stats/available": False})
        self.check_fields(
            "copilot-github-status",
            {
                "details/status/indicator": "minor",
                "details/status/description": "Copilot degraded",
                "details/status/components": ["Copilot (degraded performance)"],
                "details/status/incidents": ["Slow Copilot completions"],
                "details/status/latestUpdate": "Completions are slower than usual.",
                "details/status/url": "https://www.githubstatus.com",
            },
        )

    def test_cli_plan_providers(self):
        self.check_fields(
            "kimi-code-success",
            {
                "ok": True,
                "summary/detail": "Kimi Code",
                "summary/pct": 45,
                "quotaWindows/0/detail": "30 / 100",
                "quotaWindows/2/detail": "$2.5 left",
                "details/codePlan/booster/balance": 2.5,
                "details/keyValid": False,
            },
        )
        self.assertEqual(
            [{k: w[k] for k in ("name", "seconds")} for w in fixture("kimi-code-success")["details"]["codePlan"]["windows"]],
            [{"name": "", "seconds": 18000}, {"name": "", "seconds": 604800}],
        )
        self.check_fields(
            "kimi-code-exhausted",
            {
                "ok": True,
                "summary/pct": 100,
                "quotaWindows/0/detail": "Credits used up",
                "summary/hasChart": False,
                "chartWindows": [],
                "details/codePlan/exhausted": True,
            },
        )
        self.check_fields(
            "cursor-success",
            {
                "summary/detail": "Pro",
                "summary/pct": 62.5,
                "quotaWindows/0/detail": "$12.5 / $20",
                "quotaWindows/3/detail": "$3 / $10",
                "quotaWindows/0/resetAt": 1790495647,
                "details/resetAt": 1790495647,
                "details/stats/available": True,
                "details/stats/totalTokens": 198998,
                "details/stats/totalCostUSD": 1.56585075,
                "details/stats/favoriteModel": "claude-4.5-sonnet",
                "details/stats/totalSessions": 2,
                "details/stats/totalRequests": 3,
                "details/stats/longestSessionMs": 600000,
                "details/stats/longestSessionMessages": 2,
                "details/stats/models/default/requests": 1,
                "details/stats/dailyUnit": "tokens",
                "details/stats/partial": False,
            },
        )
        self.check_fields(
            "cursor-free",
            {
                "ok": True,
                "summary/detail": "Free",
                "summary/pct": 0,
                "quotaWindows/0/detail": "0% of included usage",
                "details/nextUpgrade/name": "Pro",
                "details/source": "cli",
                "details/stats/available": False,
            },
        )
        self.assertEqual(len(fixture("cursor-free")["quotaWindows"]), 3)
        self.check_fields(
            "cline-success",
            {
                "ok": True,
                "details/stats/available": True,
                "details/stats/totalSessions": 3,
                "details/stats/totalTokens": 97365,
                "details/stats/totalCostUSD": 0.47,
                "details/stats/favoriteModel": "anthropic/claude-sonnet-4.5",
                "details/stats/topWorkspaces/0": {"name": "ai-usage-widget", "sessions": 2},
                "details/stats/longestSessionMs": 600000,
                "quotaWindows/2/detail": "97.4k tokens · 3 sessions · $0.47",
                "summary/text": "97.4k",
                "summary/detail": "last 30 days",
                "details/periods/1/sessions": 3,
                "details/periods/1/tokens": 97365,
            },
        )
        self.assertEqual(fixture("cline-success")["details"]["stats"]["models"]["anthropic/claude-sonnet-4.5"]["sessions"], 2)
        self.check_fields(
            "cline-gatus-status",
            {"details/status/indicator": "major", "details/status/components": ["Web App (down)"], "details/status/url": "https://status.cline.bot"},
        )

    def test_muse(self):
        self.check_fields(
            "muse-success",
            {
                "details/hasLogin": True,
                "details/stats/totalTokens": 150000,
                "details/stats/totalOutputTokens": 30000,
                "details/stats/model": "muse-spark-1.3-contributor",
                "summary/text": "150k",
                "summary/detail": "muse-spark-1.3-contributor",
                "details/stats/totalCostUSD": 0.009,
                "quotaWindows/1/detail": "$0.01",
                "summary/pct": 0,
                "details/stats/available": True,
                "details/stats/activeDays": 3,
                "details/stats/longestStreak": 3,
                "details/stats/peakHour": 14,
                "details/stats/dailyUnit": "tokens",
                "details/stats/topWorkspaces/0/name": "ai-usage-widget",
                "details/stats/favoriteModel": "muse-spark-1.3-contributor",
            },
        )
        self.assertEqual([d["total"] for d in fixture("muse-success")["details"]["stats"]["dailySeries"]], [10000, 8000, 12000])
        self.assertTrue(all(not w["showMeter"] and w["resetAt"] == 0 for w in fixture("muse-success")["quotaWindows"]))
        self.check_fields(
            "muse-unpriced",
            {
                "ok": True,
                "details/stats/totalTokens": 0,
                "details/stats/totalCostUSD": 0,
                "details/stats/available": True,
                "details/stats/totalSessions": 2,
                "details/stats/totalToolCalls": 3,
            },
        )
        self.check_fields(
            "muse-quota-success",
            {
                "ok": True,
                "summary/pct": 26,
                "summary/text": "26%",
                "quotaWindows/0/pct": 26,
                "quotaWindows/0/resetAt": 1788528365,
                "quotaWindows/0/showMeter": True,
                "quotaWindows/1/pct": 9,
                "quotaWindows/1/resetAt": 1788739200,
                "details/current/available": True,
                "details/weekly/available": True,
                "historyValues": {"mu": 150000, "mc": 26, "mw": 9},
            },
        )
        self.assertEqual(sorted({w["key"] for w in fixture("muse-quota-success")["chartWindows"]}), ["mc", "mw"])
        self.assertTrue(all(w["resetAt"] > 1000000000 for w in fixture("muse-quota-success")["quotaWindows"] if w["showMeter"]))
        self.check_fields("muse-quota-only", {"ok": True, "summary/pct": 26, "details/stats/available": False})

    def test_error_messages(self):
        for name, message in {
            "claude-missing-credentials": "Claude not logged in",
            "claude-offline": "offline",
            "claude-rate-limited": "rate limited",
            "antigravity-not-running": "Antigravity is not running in IDE",
            "antigravity-missing": "Antigravity not configured",
            "kiro-missing": "Kiro: no local usage data found",
            "mistral-invalid-key": "Invalid API key (401)",
            "mistral-missing": "Mistral: no API key configured",
            "openrouter-missing": "OpenRouter: no API key configured",
            "zai-missing": "Z.AI: no token configured",
            "copilot-missing": "Copilot: no token configured",
            "deepseek-error": "DeepSeek: Invalid DeepSeek API key",
            "deepseek-missing": "DeepSeek: no API key configured",
            "kimi-missing": "Kimi: no Moonshot API key or Kimi Code login",
            "cline-missing": "Cline: no sessions yet — run cline once",
            "cursor-missing": "Cursor: not signed in — run cursor-agent login",
            "cursor-expired": "Cursor: login expired — run cursor-agent login",
            "muse-error": "Muse: no sessions yet",
            "muse-missing": "Muse: not installed",
            "muse-malformed": "Muse: not installed",
        }.items():
            self.check_fields(name, {"ok": False, "error": message})
        for name in ("claude-missing-credentials", "claude-offline", "claude-rate-limited"):
            self.check_fields(name, {"stale": True})
        self.check_fields("claude-missing-credentials", {"details/hasOAuth": False})
        self.check_fields("cline-missing", {"details/stats/available": False})
        self.check_fields("muse-error", {"details/hasLogin": True, "details/stats/available": False})
        self.check_fields("muse-missing", {"details/hasLogin": False})
        for name, prefix in (("kiro-error", "Kiro: No Kiro state found"), ("copilot-error", "Copilot: GitHub token cannot")):
            self.check_fields(name, {"ok": False})
            self.assertTrue(fixture(name)["error"].startswith(prefix))
        self.check_fields("grok-missing", {"ok": False})
        self.assertIn("grok --oauth", fixture("grok-missing")["error"])
        self.check_fields("mistral-missing", {"details/status/indicator": "", "details/status/url": "https://status.mistral.ai"})
        self.check_fields("zai-missing", {"details/status/indicator": "", "details/status/url": ""})

    def test_window_selection(self):
        for name, dates in (("claude-success", ["2026-07-22", "2026-07-23"]), ("openai-codex-success", ["2026-07-23", "2026-07-24"])):
            self.assertEqual([d["date"] for d in fixture(name)["details"]["stats"]["dailyTokens"]], dates)
        for name, keys in {
            "claude-scoped-week": ["session", "weekly", "weekly_fable"],
            "zai-today": ["zai_tokens", "zai_tokens_long", "zai_tools", "zai_today"],
            "cursor-success": ["cursor_total", "cursor_auto", "cursor_api", "cursor_on_demand"],
            "cline-success": ["cline_today", "cline_7d", "cline_30d"],
            "muse-success": ["muse_tokens", "muse_spend"],
            "muse-unpriced": ["muse_tokens"],
            "muse-quota-success": ["muse_current", "muse_weekly", "muse_tokens", "muse_spend"],
            "muse-quota-only": ["muse_current", "muse_weekly"],
        }.items():
            with self.subTest(fixture=name):
                self.assertEqual([w["key"] for w in fixture(name)["quotaWindows"]], keys)
        for name, keys in (("claude-success", ["s", "s", "w", "w"]), ("openai-codex-success", ["cp", "cp", "cw", "cw"])):
            self.assertEqual([w["key"] for w in fixture(name)["chartWindows"]], keys)
        self.assertEqual(
            [w["id"] for w in fixture("openai-codex-success")["chartWindows"]], ["codex_primary", "codex_day", "codex_weekly", "codex_monthly"]
        )
        for name, raw in (("antigravity-success", False), ("kiro-success", False), ("mistral-success", True), ("deepseek-success", True)):
            windows = fixture(name)["chartWindows"]
            self.assertEqual(len(windows), 4)
            self.assertTrue(all(w["raw"] == raw and not w["resets"] for w in windows))
        for name in ("antigravity-success", "kiro-success", "kimi-code-success"):
            self.assertEqual([w["label"] for w in fixture(name)["chartWindows"]], ["5H", "24H", "7D", "30D"])
        for name, key in (("claude-success", "scopedWeekly"), ("claude-scoped-week", "scopedWeekly")):
            self.assertEqual(len(fixture(name)["details"][key]), 1)
        for name in ("openai-codex-success", "openai-legacy-windows"):
            self.assertEqual(len(fixture(name)["details"]["codex"]["additional"]), 1)
        self.assertEqual(len(fixture("antigravity-success")["details"]["groups"]), 2)
