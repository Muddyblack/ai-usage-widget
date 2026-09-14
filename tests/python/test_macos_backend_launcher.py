"""The entry point of the backend frozen into `AI Usage.app`.

The Swift app talks to this once it is bundled. These portable tests check
CLI routing; macOS CI also builds and smoke-tests the frozen backend.

What is checked is the routing and the argument passing, which is all the
launcher does. Whether PyInstaller can freeze it is a different question and
needs a Mac.
"""

import contextlib
import importlib.util
import io
import json
import os
import unittest
from unittest import mock

from _support import REPO, IsolatedHomeTest

LAUNCHER = os.path.join(REPO, "macos", "packaging", "launcher.py")
SPEC = os.path.join(REPO, "macos", "packaging", "ai-usage-backend.spec")


def load_launcher():
    """Imported by path: macos/packaging is not a package, and the frozen build
    hands PyInstaller this file directly."""
    spec = importlib.util.spec_from_file_location("ai_usage_launcher", LAUNCHER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class LauncherTest(IsolatedHomeTest):
    @classmethod
    def setUpClass(cls):
        if not os.path.isfile(LAUNCHER):
            raise unittest.SkipTest("macos/ is not checked out")
        cls.launcher = load_launcher()

    def test_history_is_routed_to_historyio_without_its_own_word(self):
        with mock.patch.object(self.launcher, "history_main", return_value=0) as history:
            with mock.patch.object(self.launcher, "usage_main") as usage:
                self.assertEqual(self.launcher.main(["history", "autosave", "--stdin"]), 0)
        history.assert_called_once_with(["autosave", "--stdin"])
        usage.assert_not_called()

    def test_everything_else_goes_to_the_usage_cli_untouched(self):
        for argv in ([], ["--all"], ["--provider", "claude,openai"], ["--normalize"], ["--list"]):
            with self.subTest(argv=argv):
                with mock.patch.object(self.launcher, "usage_main", return_value=0) as usage:
                    with mock.patch.object(self.launcher, "history_main") as history:
                        self.assertEqual(self.launcher.main(argv), 0)
                usage.assert_called_once_with(argv)
                history.assert_not_called()

    def test_a_provider_called_history_would_still_reach_the_usage_cli(self):
        """`history` only means the history CLI as the *first* word."""
        with mock.patch.object(self.launcher, "usage_main", return_value=0) as usage:
            with mock.patch.object(self.launcher, "history_main") as history:
                self.launcher.main(["--provider", "history"])
        usage.assert_called_once_with(["--provider", "history"])
        history.assert_not_called()

    # ── End to end, without mocks ───────────────────────────────────────

    def _run(self, argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = self.launcher.main(argv)
        return code, out.getvalue()

    def test_list_answers_the_same_provider_ids_the_shell_launcher_does(self):
        from aiusage import config

        code, text = self._run(["--list"])
        self.assertEqual(code, 0)
        self.assertEqual(text.split(), config.ALL_PROVIDERS)

    def test_history_autoload_answers_the_contract_shape(self):
        code, text = self._run(["history", "autoload"])
        self.assertEqual(code, 0)
        # An untouched throwaway home has no history file; the answer is still
        # a well-formed one rather than an error.
        self.assertEqual(json.loads(text), {"ok": True, "empty": True})

    def test_help_is_answered_rather_than_treated_as_a_provider(self):
        code, text = self._run(["--help"])
        self.assertEqual(code, 0)
        self.assertIn("get-ai-usage", text)


class SpecTest(unittest.TestCase):
    """The PyInstaller spec, read as text — it cannot be executed off a Mac."""

    @classmethod
    def setUpClass(cls):
        if not os.path.isfile(SPEC):
            raise unittest.SkipTest("macos/ is not checked out")
        with open(SPEC, encoding="utf-8") as fh:
            cls.text = fh.read()

    def test_it_freezes_the_launcher_that_is_actually_here(self):
        self.assertIn('Analysis(\n    ["launcher.py"]', self.text)
        self.assertTrue(os.path.isfile(LAUNCHER))

    def test_the_package_path_resolves_to_the_backend(self):
        """SPECPATH is macos/packaging, so two levels up is the repository root
        and the tools directory is under it. Wrong, and PyInstaller freezes an
        empty program."""
        self.assertIn('os.path.join(SPECPATH, "..", "..")', self.text)
        self.assertTrue(os.path.isdir(os.path.join(REPO, "package", "contents", "tools", "aiusage")))

    def test_the_modules_reached_only_through_the_registry_are_named(self):
        """aiusage.providers and aiusage.normalize are imported by name at
        runtime, so PyInstaller's dependency graph does not find them."""
        for module in ("aiusage.normalize", "aiusage.providers", "psutil"):
            with self.subTest(module=module):
                self.assertIn(f'"{module}"', self.text)

    def test_psutil_is_pinned_and_is_the_only_dependency(self):
        """The backend is standard-library-only apart from psutil; anything
        else appearing here means the freeze grew a dependency nobody meant."""
        path = os.path.join(REPO, "macos", "packaging", "requirements.txt")
        with open(path, encoding="utf-8") as fh:
            requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]
        self.assertEqual(len(requirements), 1, requirements)
        self.assertRegex(requirements[0], r"^psutil==\d+\.\d+(\.\d+)?$")

    def test_it_builds_a_directory_rather_than_a_single_file(self):
        """A --onefile build unpacks itself on every run, and the app runs this
        on every poll."""
        self.assertIn("COLLECT(", self.text)
        self.assertIn('name="backend"', self.text)
        self.assertNotIn("onefile", self.text.lower().replace("--onefile build", ""))

    def test_the_app_looks_for_it_where_the_spec_puts_it(self):
        """COLLECT names the directory; BackendRunner looks inside it."""
        runner = os.path.join(REPO, "macos", "Sources", "AIUsage", "Backend", "BackendRunner.swift")
        with open(runner, encoding="utf-8") as fh:
            swift = fh.read()
        self.assertIn("Contents/Resources/backend", swift)
        self.assertIn('appendingPathComponent("ai-usage-backend")', swift)
        self.assertIn('name="ai-usage-backend"', self.text)

        build = os.path.join(REPO, "macos", "scripts", "build-app.sh")
        with open(build, encoding="utf-8") as fh:
            script = fh.read()
        self.assertRegex(script, r'cp -R .*backend-dist/backend" "\$APP/Contents/Resources/backend"')


if __name__ == "__main__":
    unittest.main()
