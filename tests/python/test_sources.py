"""Provider sources: what each can be read from, which one is used, and the
proxy setting that applies to every request they make."""

import os
import unittest
from unittest import mock

from _support import IsolatedHomeTest
from aiusage import config, sources
from aiusage.normalize import normalize
from aiusage.providers import antigravity, copilot, cursor, kilo, kiro, ollama

NOW = 1790841600


def choose(provider, source):
    return mock.patch.dict(os.environ, {f"WIDGET_SOURCE_{provider.upper()}": source})


class CandidatesTest(IsolatedHomeTest):
    def test_auto_keeps_the_default_order(self):
        self.assertEqual(sources.candidates("cursor", ("cli", "ide")), ["cli", "ide"])

    def test_an_explicit_choice_is_strict(self):
        with choose("cursor", "ide"):
            self.assertEqual(sources.candidates("cursor", ("cli", "ide")), ["ide"])

    def test_an_unknown_choice_is_ignored_not_fatal(self):
        with choose("cursor", "browser"):
            self.assertEqual(sources.candidates("cursor", ("cli", "ide")), ["cli", "ide"])

    def test_the_choice_is_read_from_the_settings_file(self):
        self.write("config.json", {"sources": {"cursor": "ide"}})
        config.reset_settings_cache()
        self.assertEqual(sources.preferred("cursor"), "ide")
        self.assertEqual(sources.preferred("kiro"), "auto")


class DescribeTest(IsolatedHomeTest):
    def describe(self, provider, usage, ok=True):
        return sources.describe(provider, {"usage": usage}, {"ok": ok})

    def states(self, block):
        return {option["id"]: option["state"] for option in block["options"]}

    def test_the_source_that_answered_is_working_and_the_rest_are_not(self):
        self.write(".cursor/auth.json", {"accessToken": "x"})
        block = self.describe("cursor", {"source": "ide", "usage": {}})
        self.assertEqual((block["active"], self.states(block)), ("ide", {"cli": "ready", "ide": "working"}))

    def test_the_active_source_failing_is_failing(self):
        block = self.describe("cursor", {"source": "cli", "error": "login expired"}, ok=False)
        self.assertEqual(self.states(block)["cli"], "failing")

    def test_a_source_nothing_suggests_is_missing(self):
        block = self.describe("kiro", {})
        self.assertEqual(self.states(block), {"cli": "missing", "ide": "missing"})
        self.assertEqual(block["active"], "")

    def test_without_a_recorded_source_the_first_set_up_one_is_assumed(self):
        self.write(".config/Kiro/User/globalStorage/state.vscdb", "")
        self.assertEqual(self.describe("kiro", {})["active"], "ide")

    def test_the_users_choice_is_reported_and_unknown_ones_are_not(self):
        with choose("kiro", "ide"):
            self.assertEqual(self.describe("kiro", {})["selected"], "ide")
        with choose("kiro", "browser"):
            self.assertEqual(self.describe("kiro", {})["selected"], "auto")

    def test_a_crashing_probe_never_costs_the_tab(self):
        broken = sources.Source("x", "cli", "x", "x", lambda: 1 / 0)
        self.assertFalse(sources._safe_probe(broken))

    def test_unknown_kinds_fall_back_and_unregistered_providers_have_none(self):
        self.assertIsNone(sources.describe("claude", {}, {"ok": True}))
        self.assertTrue(all(o["kind"] in sources.KINDS for o in self.describe("antigravity", {})["options"]))

    def test_every_registered_provider_has_unique_ids_and_known_kinds(self):
        for provider_id, spec in sources._registry().items():
            ids = [source.id for source in spec.sources]
            with self.subTest(provider=provider_id):
                self.assertEqual(len(ids), len(set(ids)))
                self.assertTrue(all(source.kind in sources.KINDS and source.label and source.detail for source in spec.sources))

    def test_normalize_attaches_sources_to_error_envelopes_too(self):
        result = normalize({"id": "cursor", "now": NOW, "inputs": {"usage": {}}})
        self.assertFalse(result["ok"])
        self.assertEqual([o["id"] for o in result["sources"]["options"]], ["cli", "ide"])
        self.assertNotIn("sources", normalize({"id": "claude", "now": NOW, "inputs": {}}))


class ChoiceIsHonouredTest(IsolatedHomeTest):
    def test_cursor_reads_only_the_chosen_source(self):
        with mock.patch.object(cursor, "_agent_token", return_value="agent"), mock.patch.object(cursor, "_ide_token", return_value="ide"):
            self.assertEqual(cursor._cursor_token(), ("agent", "cli"))
            with choose("cursor", "ide"):
                self.assertEqual(cursor._cursor_token(), ("ide", "ide"))
        with mock.patch.object(cursor, "_agent_token", return_value="agent"), mock.patch.object(cursor, "_ide_token", return_value=""):
            with choose("cursor", "ide"):
                self.assertEqual(cursor._cursor_token(), ("", ""))

    def test_kiro_does_not_fall_back_from_an_explicit_choice(self):
        readers = {"cli": lambda: {"error": "expired"}, "ide": lambda: {"planType": "pro"}}
        with mock.patch.dict(kiro._READERS, readers):
            self.assertEqual(kiro.get_kiro_usage(), {"planType": "pro"})
            with choose("kiro", "cli"):
                self.assertEqual(kiro.get_kiro_usage(), {"error": "expired"})

    def test_ollama_uses_the_chosen_key(self):
        with (
            mock.patch.dict(os.environ, {"OLLAMA_API_KEY": "own"}),
            mock.patch.object(ollama, "_opencode_key", return_value="from-opencode"),
        ):
            self.assertEqual(ollama._resolve_key(), ("own", "key"))
            with choose("ollama", "opencode"):
                self.assertEqual(ollama._resolve_key(), ("from-opencode", "opencode"))

    def test_copilot_tries_the_chosen_login_only(self):
        logins = {"key": lambda: ("k", ""), "editor": lambda: ("e", "user"), "cli": lambda: ("", "")}
        with mock.patch.dict(copilot._LOGINS, logins):
            self.assertEqual(copilot._github_login(), ("k", "", "key"))
            with choose("copilot", "editor"):
                self.assertEqual(copilot._github_login(), ("e", "user", "editor"))
            with choose("copilot", "cli"):
                self.assertEqual(copilot._github_login(), ("", "", ""))
            self.assertEqual(copilot._github_token(), ("k", ""))

    def test_kilo_falls_back_to_the_cli_only_in_auto(self):
        self.write(".local/share/kilo/auth.json", {"kilo": {"access": "cli-token"}})
        seen = []

        def fetch(token):
            seen.append(token)
            return mock.Mock(status=401 if token == "stale" else 200, body="[]")

        with mock.patch.dict(os.environ, {"KILO_API_KEY": "stale"}), mock.patch.object(kilo, "_fetch", side_effect=fetch):
            kilo.get_kilo_usage()
            self.assertEqual(seen, ["stale", "cli-token"])
            seen.clear()
            with choose("kilo", "key"):
                kilo.get_kilo_usage()
            self.assertEqual(seen, ["stale"])

    def test_antigravity_says_which_source_stayed_silent(self):
        with mock.patch.object(antigravity, "_from_aiu", return_value=None), choose("antigravity", "aiu"):
            self.assertIn("antigravity-usage", antigravity.get_antigravity_usage()["error"])
        with (
            mock.patch.object(antigravity, "_from_aiu", return_value=None),
            mock.patch.object(antigravity, "_from_server", return_value=({"models": [], "method": "ls"}, True)),
            choose("antigravity", "server"),
        ):
            self.assertEqual(antigravity.get_antigravity_usage()["source"], "server")

    def test_antigravity_records_the_source_but_keeps_an_empty_answer_empty(self):
        with mock.patch.object(antigravity, "_from_aiu", return_value={}):
            self.assertEqual(antigravity.get_antigravity_usage(), {})
        with mock.patch.object(antigravity, "_from_aiu", return_value={"models": []}):
            self.assertEqual(antigravity.get_antigravity_usage()["source"], "aiu")


class ProxyTest(IsolatedHomeTest):
    def clean(self):
        return mock.patch.dict(os.environ, {}, clear=False)

    def test_settings_validation(self):
        self.assertEqual(config.proxy_settings({}), ("system", ""))
        self.assertEqual(config.proxy_settings({"proxy": {"mode": "off"}}), ("off", ""))
        self.assertEqual(config.proxy_settings({"proxy": {"mode": "http", "host": "127.0.0.1", "port": 10808}}), ("http", "http://127.0.0.1:10808"))
        self.assertEqual(
            config.proxy_settings({"proxy": {"mode": "http", "host": "http://proxy.corp/", "port": "3128"}}), ("http", "http://proxy.corp:3128")
        )
        for bad in (
            {"host": "", "port": 80},
            {"host": "a b", "port": 80},
            {"host": "h", "port": 0},
            {"host": "h", "port": "x"},
            {"host": "h;rm", "port": 1},
        ):
            with self.subTest(bad=bad):
                self.assertEqual(config.proxy_settings({"proxy": {"mode": "http", **bad}}), ("system", ""))
        self.assertEqual(config.proxy_settings({"proxy": "nope"}), ("system", ""))

    def test_an_http_proxy_is_exported_and_never_used_for_this_machine(self):
        with mock.patch.dict(os.environ, {}, clear=False):
            for name in ("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy", "NO_PROXY", "no_proxy"):
                os.environ.pop(name, None)
            config.apply_proxy({"proxy": {"mode": "http", "host": "127.0.0.1", "port": 10808}})
            self.assertEqual(os.environ["HTTPS_PROXY"], "http://127.0.0.1:10808")
            self.assertIn("localhost", os.environ["NO_PROXY"])

    def test_an_environment_proxy_wins_and_off_disables_every_proxy(self):
        with mock.patch.dict(os.environ, {"HTTPS_PROXY": "http://env:1"}):
            config.apply_proxy({"proxy": {"mode": "http", "host": "other", "port": 2}})
            self.assertEqual(os.environ["HTTPS_PROXY"], "http://env:1")
        with mock.patch.dict(os.environ, {}):
            config.apply_proxy({"proxy": {"mode": "off"}})
            self.assertEqual(os.environ["NO_PROXY"], "*")

    def test_changing_the_setting_takes_back_only_what_was_exported(self):
        with mock.patch.dict(os.environ, {"NO_PROXY": "corp.internal"}):
            os.environ.pop("HTTPS_PROXY", None)
            os.environ.pop("https_proxy", None)
            os.environ.pop("HTTP_PROXY", None)
            os.environ.pop("http_proxy", None)
            config.apply_proxy({"proxy": {"mode": "http", "host": "h", "port": 1}})
            self.assertEqual(os.environ["NO_PROXY"], "corp.internal," + config._LOOPBACK)
            config.apply_proxy({"proxy": {"mode": "system"}})
            self.assertNotIn("HTTPS_PROXY", os.environ)
            self.assertEqual(os.environ["NO_PROXY"], "corp.internal")

    def test_system_leaves_the_environment_alone(self):
        before = dict(os.environ)
        config.apply_proxy({})
        self.assertEqual(dict(os.environ), before)


if __name__ == "__main__":
    unittest.main()
