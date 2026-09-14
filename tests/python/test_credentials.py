"""Credential discovery against an isolated, throwaway home directory."""

import hashlib
import json
import os
import subprocess
import time
import unittest
from unittest import mock

from _support import IsolatedHomeTest
from aiusage import keychain, paths
from aiusage.providers import claude_credentials
from aiusage.providers.claude_credentials import get_claude_credentials
from aiusage.providers.copilot import _github_token
from aiusage.providers.grok import _resolve_api_key
from aiusage.providers.moonshot import _moonshot_key
from aiusage.providers.muse import auth_presence, configured_model
from aiusage.providers.openai_credentials import get_openai_credentials
from aiusage.providers.zai import _zai_key


class CredentialDiscoveryTest(IsolatedHomeTest):
    def setUp(self):
        super().setUp()
        self.tmp = str(self.home)
        os.makedirs(os.path.join(self.home, ".config"))

    def test_zai_sources_and_precedence(self):
        self.assertEqual(_zai_key(), "")
        self.write(".config/glm-acp-agent/credentials.json", json.dumps({"z_ai_api_key": "borrowed"}))
        self.assertEqual(_zai_key(), "borrowed")
        self.write(".config/zai/token", "file\n")
        self.assertEqual(_zai_key(), "file")
        os.environ.update({"Z_AI_API_KEY": "vendor", "ZAI_TOKEN": "native"})
        self.assertEqual(_zai_key(), "native")
        os.environ.pop("ZAI_TOKEN")
        self.assertEqual(_zai_key(), "vendor")

    def test_zai_alternate_file_and_broken_borrowed_store(self):
        self.write(".zai/token", "dot-zai\n")
        self.assertEqual(_zai_key(), "dot-zai")
        (self.home / ".zai/token").unlink()
        self.write(".config/glm-acp-agent/credentials.json", "not json")
        self.assertEqual(_zai_key(), "")
        self.write(".config/glm-acp-agent/credentials.json", '{"z_ai_api_key":null}')
        self.assertEqual(_zai_key(), "")

    def test_moonshot_sources_and_precedence(self):
        self.assertEqual(_moonshot_key(), "")
        self.write(".config/kimi/api-key", "kimi-file\n")
        self.assertEqual(_moonshot_key(), "kimi-file")
        os.environ["KIMI_API_KEY"] = "kimi-env"
        self.write(".config/moonshot/api-key", "moonshot-file\n")
        self.assertEqual(_moonshot_key(), "kimi-env")
        os.environ["MOONSHOT_API_KEY"] = "moonshot-env"
        self.assertEqual(_moonshot_key(), "moonshot-env")

    @mock.patch("aiusage.providers.copilot.shutil.which", return_value="gh")
    @mock.patch("aiusage.providers.copilot.subprocess.run")
    def test_copilot_sources_and_precedence(self, run, _which):
        run.return_value.returncode = 1
        run.return_value.stdout = ""
        self.assertEqual(_github_token(), ("", ""))
        run.return_value.returncode = 0
        run.return_value.stdout = "gh-token\n"
        self.assertEqual(_github_token(), ("gh-token", ""))
        self.write(
            ".copilot/config.json", '// User settings belong in settings.json.\n{"lastLoggedInUser":{"host":"https://github.com","login":"octocat"}}'
        )
        self.assertEqual(_github_token(), ("gh-token", "octocat"))
        self.write(".config/github-copilot/apps.json", '{"github.com:app":{"user":"editor","oauth_token":"editor-token"}}')
        self.assertEqual(_github_token(), ("editor-token", "editor"))
        self.write(".config/github-copilot/token", "file-token\n")
        self.assertEqual(_github_token(), ("file-token", ""))
        os.environ["GITHUB_TOKEN"] = "env-token"
        self.assertEqual(_github_token(), ("env-token", ""))

    @mock.patch("aiusage.providers.copilot.shutil.which", return_value="gh")
    @mock.patch("aiusage.providers.copilot.subprocess.run")
    def test_copilot_selects_exact_github_host_and_tolerates_corruption(self, run, _which):
        run.return_value.returncode = 1
        run.return_value.stdout = ""
        self.write(
            ".config/github-copilot/hosts.json",
            '{"github.company.com:x":{"user":"wrong","oauth_token":"wrong"},"github.com:y":{"user":"right","oauth_token":"token"}}',
        )
        self.assertEqual(_github_token(), ("token", "right"))
        self.write(".config/github-copilot/hosts.json", "not json")
        self.write(".config/github-copilot/apps.json", "not json")
        self.assertEqual(_github_token(), ("", ""))
        self.write(
            ".config/github-copilot/hosts.json",
            '{"ghe.example.com:x":{"user":"enterprise","oauth_token":"wrong"},"github.com:y":{"user":"right","oauth_token":"token"}}',
        )
        self.assertEqual(_github_token(), ("token", "right"))

    def test_muse_presence_and_configured_model(self):
        os.environ["MUSE_AUTH_PATH"] = os.path.join(self.tmp, "auth.json")
        self.assertFalse(auth_presence())
        with open(os.environ["MUSE_AUTH_PATH"], "w", encoding="utf-8") as fh:
            fh.write('{"providers":{"meta":{"mechanism":"oauth"}}}')
        self.assertTrue(auth_presence())
        with open(os.environ["MUSE_AUTH_PATH"], "w", encoding="utf-8") as fh:
            fh.write("not json")
        self.assertFalse(auth_presence())
        os.environ["MUSE_SETTINGS_PATH"] = os.path.join(self.tmp, "settings.json")
        self.assertEqual(configured_model(), "")
        with open(os.environ["MUSE_AUTH_PATH"], "w", encoding="utf-8") as fh:
            fh.write('{"providers":{}}')
        self.assertFalse(auth_presence())
        with open(os.environ["MUSE_SETTINGS_PATH"], "w", encoding="utf-8") as fh:
            fh.write('{"provider":"meta","model":"muse-spark-9.9"}')
        self.assertEqual(configured_model(), "muse-spark-9.9")

    def test_shared_key_resolvers_strip_and_prioritize(self):
        self.assertEqual(get_claude_credentials().get("claudeAdminApiKey", ""), "")
        self.write(".config/claude-admin-api-key", "claude-file\n")
        self.write(".claude/admin-api-key", "claude-dot\n")
        self.assertEqual(get_claude_credentials()["claudeAdminApiKey"], "claude-file")
        os.environ.update({"CLAUDE_ADMIN_API_KEY": " env-claude\n", "WIDGET_CLAUDE_ADMIN_KEY": "widget-claude"})
        self.assertEqual(get_claude_credentials()["claudeAdminApiKey"], "widget-claude")
        os.environ.pop("WIDGET_CLAUDE_ADMIN_KEY")
        self.assertEqual(get_claude_credentials()["claudeAdminApiKey"], "env-claude")
        os.environ.pop("CLAUDE_ADMIN_API_KEY")
        (self.home / ".config/claude-admin-api-key").unlink()
        self.assertEqual(get_claude_credentials()["claudeAdminApiKey"], "claude-dot")

        self.write(".config/openai-api-key", "openai-file\n")
        self.write(".openai/api-key", "openai-dot\n")
        self.assertEqual(get_openai_credentials()["openaiApiKey"], "openai-file")
        os.environ.update({"OPENAI_API_KEY": "env-openai", "WIDGET_OPENAI_API_KEY": "widget-openai"})
        self.assertEqual(get_openai_credentials()["openaiApiKey"], "widget-openai")
        os.environ.pop("WIDGET_OPENAI_API_KEY")
        self.assertEqual(get_openai_credentials()["openaiApiKey"], "env-openai")

        self.write(".config/xai/api-key", "xai-file\n")
        self.write(".config/grok/api-key", "grok-file\n")
        self.assertEqual(_resolve_api_key(), "xai-file")
        os.environ.update({"XAI_API_KEY": "xai-env", "GROK_API_KEY": "grok-env"})
        self.assertEqual(_resolve_api_key(), "xai-env")
        os.environ.update({"WIDGET_GROK_API_KEY": "widget-grok", "WIDGET_XAI_API_KEY": "widget-xai"})
        self.assertEqual(_resolve_api_key(), "widget-xai")
        os.environ.pop("WIDGET_XAI_API_KEY")
        self.assertEqual(_resolve_api_key(), "widget-grok")

    def test_shared_resolver_strips_newline(self):
        from aiusage.http import resolve_key

        os.environ["WIDGET_TEST_KEY"] = "secret-value\n"
        self.assertEqual(resolve_key("WIDGET_TEST_KEY", ""), "secret-value")


class ClaudeKeychainTest(IsolatedHomeTest):
    """macOS keeps the Claude Code login in the Keychain, not in a file.

    Every test here drives a stand-in for `/usr/bin/security` and asserts on
    the arguments it was called with, so the suite says the same thing on a
    Linux runner as it would on a Mac.
    """

    HOUR_MS = 60 * 60 * 1000

    def setUp(self):
        super().setUp()
        self.calls = []
        # IsolatedHomeTest clears the environment; `security` is asked for the
        # item under the account name of whoever is logged in.
        os.environ["USER"] = "tester"

    def _security(self, items):
        """A fake `security` that answers from `items` — {service: password}.
        Anything not in it exits 44, the way errSecItemNotFound comes back."""

        def run(argv, **kwargs):
            self.calls.append(argv)
            service = argv[argv.index("-s") + 1]
            result = mock.Mock()
            if service in items:
                result.returncode, result.stdout = 0, items[service]
            else:
                result.returncode, result.stdout = 44, ""
            return result

        return mock.patch.object(keychain.subprocess, "run", side_effect=run)

    def _oauth(self, token, expires_in_ms):
        return json.dumps({"claudeAiOauth": {"accessToken": token, "expiresAt": time.time() * 1000 + expires_in_ms}})

    def macos(self, on=True):
        return mock.patch.object(paths, "IS_MACOS", on)

    def test_keychain_is_not_touched_off_macos(self):
        self.write(".claude/.credentials.json", self._oauth("from-file", self.HOUR_MS))
        with self.macos(False), self._security({"Claude Code-credentials": self._oauth("from-keychain", self.HOUR_MS)}):
            creds = get_claude_credentials()
        self.assertEqual(creds["claudeAiOauth"]["accessToken"], "from-file")
        self.assertEqual(self.calls, [])

    def test_keychain_read_on_macos(self):
        os.environ["USER"] = "tester"
        with self.macos(), self._security({"Claude Code-credentials": self._oauth("from-keychain", self.HOUR_MS)}):
            creds = get_claude_credentials()
        self.assertEqual(creds["claudeAiOauth"]["accessToken"], "from-keychain")
        argv = self.calls[0]
        self.assertEqual(argv[:3], ["/usr/bin/security", "find-generic-password", "-a"])
        self.assertIn("tester", argv)
        # -w keeps `security` from printing the item's attributes around the
        # secret, which is what makes the output parseable as the JSON itself.
        self.assertIn("-w", argv)

    def test_stale_file_loses_to_a_live_keychain_token(self):
        """The case this whole path exists for: Claude Code moved the login
        into the Keychain and left the old file behind, so the file answers
        "token expired" while a working token sits next to it."""
        self.write(".claude/.credentials.json", self._oauth("stale", -self.HOUR_MS))
        with self.macos(), self._security({"Claude Code-credentials": self._oauth("live", self.HOUR_MS)}):
            creds = get_claude_credentials()
        self.assertEqual(creds["claudeAiOauth"]["accessToken"], "live")

    def test_live_file_wins_over_an_expired_keychain_token(self):
        """The mirror image: a session that could not write to the Keychain —
        over SSH, say — logs in to the file instead."""
        self.write(".claude/.credentials.json", self._oauth("live", self.HOUR_MS))
        with self.macos(), self._security({"Claude Code-credentials": self._oauth("stale", -self.HOUR_MS)}):
            creds = get_claude_credentials()
        self.assertEqual(creds["claudeAiOauth"]["accessToken"], "live")

    def test_both_expired_keeps_the_later_one(self):
        self.write(".claude/.credentials.json", self._oauth("older", -2 * self.HOUR_MS))
        with self.macos(), self._security({"Claude Code-credentials": self._oauth("newer", -self.HOUR_MS)}):
            creds = get_claude_credentials()
        self.assertEqual(creds["claudeAiOauth"]["accessToken"], "newer")

    def test_missing_item_falls_back_to_the_file(self):
        self.write(".claude/.credentials.json", self._oauth("from-file", self.HOUR_MS))
        with self.macos(), self._security({}):
            creds = get_claude_credentials()
        self.assertEqual(creds["claudeAiOauth"]["accessToken"], "from-file")

    def test_nothing_anywhere_is_an_empty_answer(self):
        with self.macos(), self._security({}):
            self.assertEqual(get_claude_credentials(), {})

    def test_unreadable_keychain_payload_is_ignored(self):
        """`security` exited 0 but the password is not the JSON document —
        a hand-made item, or a format change — which is not a credential."""
        self.write(".claude/.credentials.json", self._oauth("from-file", self.HOUR_MS))
        with self.macos(), self._security({"Claude Code-credentials": "not json"}):
            creds = get_claude_credentials()
        self.assertEqual(creds["claudeAiOauth"]["accessToken"], "from-file")

    def test_security_missing_or_hung_is_survivable(self):
        self.write(".claude/.credentials.json", self._oauth("from-file", self.HOUR_MS))
        for error in (OSError("no such file"), subprocess.TimeoutExpired("security", 5)):
            with self.subTest(error=type(error).__name__):
                with self.macos(), mock.patch.object(keychain.subprocess, "run", side_effect=error):
                    creds = get_claude_credentials()
                self.assertEqual(creds["claudeAiOauth"]["accessToken"], "from-file")

    def test_config_dir_keys_both_the_item_and_the_file(self):
        """Claude Code treats a second CLAUDE_CONFIG_DIR as a second login: the
        file moves with it, and the Keychain item is keyed by a digest of the
        variable as written."""
        os.environ["CLAUDE_CONFIG_DIR"] = str(self.home / "alt")
        digest = hashlib.sha256(os.environ["CLAUDE_CONFIG_DIR"].encode("utf-8")).hexdigest()[:8]
        service = f"Claude Code-credentials-{digest}"
        self.assertEqual(claude_credentials.keychain_service(), service)

        with self.macos(), self._security({service: self._oauth("scoped", self.HOUR_MS)}):
            creds = get_claude_credentials()
        self.assertEqual(creds["claudeAiOauth"]["accessToken"], "scoped")

        self.write("alt/.credentials.json", self._oauth("scoped-file", 2 * self.HOUR_MS))
        with self.macos(), self._security({}):
            creds = get_claude_credentials()
        self.assertEqual(creds["claudeAiOauth"]["accessToken"], "scoped-file")

    def test_plain_service_name_is_tried_after_the_derived_one(self):
        """The digest is reverse-engineered, not documented. An install that
        keyed the item some other way still has a plain-named item to find."""
        os.environ["CLAUDE_CONFIG_DIR"] = str(self.home / "alt")
        with self.macos(), self._security({"Claude Code-credentials": self._oauth("plain", self.HOUR_MS)}):
            creds = get_claude_credentials()
        self.assertEqual(creds["claudeAiOauth"]["accessToken"], "plain")
        self.assertEqual(len(self.calls), 2)

    def test_admin_key_follows_the_config_dir(self):
        os.environ["CLAUDE_CONFIG_DIR"] = str(self.home / "alt")
        self.write("alt/admin-api-key", "scoped-admin\n")
        with self.macos(False):
            self.assertEqual(get_claude_credentials()["claudeAdminApiKey"], "scoped-admin")


if __name__ == "__main__":
    unittest.main()
