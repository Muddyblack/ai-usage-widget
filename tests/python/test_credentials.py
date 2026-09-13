"""Credential discovery against an isolated, throwaway home directory."""

import json
import os
import unittest
from unittest import mock

from _support import IsolatedHomeTest
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


if __name__ == "__main__":
    unittest.main()
