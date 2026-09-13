"""Terminal rendering tests for every recorded provider fixture."""

import io
import json
import os
import unittest
from unittest import mock

from _support import fixture, provider_fixtures
from aiusage import cli


class Terminal(io.StringIO):
    encoding = "utf-8"

    def isatty(self):
        return True


class CliRenderingTest(unittest.TestCase):
    def test_every_fixture_renders_portably_without_secrets_or_whitespace(self):
        names = provider_fixtures()
        for name in names:
            with self.subTest(fixture=name):
                provider = fixture(name)
                env = {"schemaVersion": 1, "updatedAt": 0, "active": "", "providers": [provider]}
                table = self.render(env, "--color", "never")
                ascii_table = self.render(env, "--color", "never", "--ascii")
                compact = self.render(env, "--compact", "--color", "never")
                label = provider.get("label") or provider.get("id") or "?"
                self.assertIn(label, table)
                self.assertIn(label, compact)
                self.assertNotRegex(table, r"secret|sk-ant-|sk-oauth|gh-secret|zai-secret|xai-secret|ds-secret|or-secret|codex-secret")
                self.assertFalse(any(line.endswith(" ") for line in table.splitlines()))
                self.assertNotIn("\033", table)
                self.assertNotRegex(ascii_table, "[█░─]")
                self.assertTrue(all(c.isprintable() or c.isspace() for c in ascii_table))

    def test_errors_values_and_compact_headlines_are_visible(self):
        for name, text in {
            "claude-missing-credentials": "not logged in",
            "claude-offline": "offline",
            "claude-rate-limited": "rate limited",
            "zai-invalid-token": "Invalid Z.AI token",
            "antigravity-not-running": "not running",
        }.items():
            with self.subTest(fixture=name):
                self.assertIn(text, self.table(name))
        self.assertRegex(self.table("claude-success"), r"5-hour session.*23%")
        self.assertIn("61%", self.table("claude-success"))
        self.assertRegex(self.table("claude-success"), r"\[#+-*\]")
        self.assertRegex(self.table("zai-today"), r"Today \(Aug 11\) +41\.18M tokens +370 calls")
        self.assertNotRegex(self.table("zai-today"), r"Today .*\[")
        self.assertIn("$", self.compact("kimi-success"))
        self.assertIn("150k", self.compact("muse-success"))
        self.assertNotIn("\n", self.compact("claude-success"))
        self.assertRegex(self.table("kimi-success"), r"Available balance +\$")
        self.assertRegex(self.table("kimi-success"), r"(?m)^Kimi")
        self.assertNotRegex(self.table("kimi-success"), r"Available balance +\[")
        self.assertRegex(self.table("muse-success"), r"Tokens +150k")
        self.assertRegex(self.table("muse-success"), r"Spend \(est\.\) +\$0\.01")
        self.assertNotRegex(self.table("muse-success"), r"Tokens +\[")
        self.assertIn("unlimited", self.table("openrouter-unlimited"))

    def test_color_style_emits_escapes_only_when_enabled(self):
        self.assertIn("\033", self.table("claude-success", color=True))
        self.assertNotIn("\033", self.table("claude-success", color=False))
        with mock.patch.dict(os.environ, {"NO_COLOR": "1", "TERM": "xterm"}):
            self.assertNotIn("\033", self.render(self.env("claude-success"), "--color", "auto"))

    def test_argument_validation_and_piped_json(self):
        for argv in (["--provider", "nope"], ["--color", "sideways"]):
            with self.subTest(argv=argv), mock.patch("sys.stderr", new=io.StringIO()):
                self.assertEqual(cli.main(argv), 2)

        source = io.StringIO("not json")
        with (
            mock.patch.object(cli, "_stdin_envelope_waiting", return_value=True),
            mock.patch("sys.stdin", new=source),
            mock.patch("sys.stderr", new=io.StringIO()),
        ):
            self.assertEqual(cli.main([]), 2)

        source = io.StringIO(json.dumps(self.env("claude-success")))
        output = io.StringIO()
        with (
            mock.patch.object(cli, "_stdin_envelope_waiting", return_value=True),
            mock.patch("sys.stdin", new=source),
            mock.patch("sys.stdout", new=output),
        ):
            self.assertEqual(cli.main(["--json", "--provider", "zai"]), 0)
        self.assertEqual(json.loads(output.getvalue())["providers"], [])

        output = io.StringIO()
        with mock.patch("sys.stdout", new=output):
            self.assertEqual(cli.main(["--list"]), 0)
        self.assertIn("claude\n", output.getvalue())
        original = self.env("claude-success")
        self.assertEqual(json.loads(self.render(original, "--json")), original)
        self.assertNotIn("Claude", self.render(original, "--provider", "zai", "--color", "never"))
        original["active"] = "claude"
        filtered = json.loads(self.render(original, "--provider", "zai", "--json"))
        self.assertEqual((filtered["providers"], filtered["active"]), ([], ""))

    @staticmethod
    def env(name):
        return {"schemaVersion": 1, "updatedAt": 0, "active": "", "providers": [fixture(name)]}

    def table(self, name, color=False):
        return self.render(self.env(name), "--color", "always" if color else "never", "--ascii").rstrip("\n")

    def compact(self, name):
        result = self.render(self.env(name), "--compact", "--color", "never")
        self.assertEqual(len(result.splitlines()), 1)
        return result.rstrip("\n")

    def render(self, env, *args):
        output = Terminal()
        with (
            mock.patch("sys.stdin", io.StringIO(json.dumps(env))),
            mock.patch("sys.stdout", output),
            mock.patch.object(cli, "_stdin_envelope_waiting", return_value=True),
            mock.patch.object(cli.envelope, "build", side_effect=AssertionError("piped envelope must not refetch")),
        ):
            self.assertEqual(cli.main(list(args)), 0)
        return output.getvalue()


if __name__ == "__main__":
    unittest.main()
