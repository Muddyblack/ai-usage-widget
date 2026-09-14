"""Where the providers look on macOS.

A Mac keeps some of these files somewhere else than Linux does, and two CLIs
keep their login in the Keychain rather than in a file at all. Every test here
drives the platform flag and a stand-in for `/usr/bin/security`, so the suite
says the same thing on a Linux runner as it would on a Mac.
"""

import os
import unittest
from pathlib import Path
from unittest import mock

from _support import IsolatedHomeTest, env_without_xdg
from aiusage import keychain, paths
from aiusage.providers.cursor import _agent_token
from aiusage.providers.grok import grok_home
from aiusage.providers.kiro import _cli_db, _ide_db
from aiusage.providers.muse_quota import _api_key as _muse_api_key
from aiusage.providers.openai_credentials import codex_home, get_openai_credentials


class MacOSPathHelpersTest(unittest.TestCase):
    def platform(self, windows=False, macos=False):
        return mock.patch.multiple(paths, IS_WINDOWS=windows, IS_MACOS=macos)

    def test_data_home_dirs_offer_application_support_on_macos(self):
        library = os.path.expanduser("~/Library/Application Support")
        share = os.path.expanduser("~/.local/share")
        with mock.patch.dict(os.environ, env_without_xdg(), clear=True):
            with self.platform(macos=True):
                self.assertEqual(paths.data_home_dirs(), [share, library])
            with self.platform():
                self.assertEqual(paths.data_home_dirs(), [share])

    def test_data_home_dirs_keep_xdg_first(self):
        library = os.path.expanduser("~/Library/Application Support")
        env = env_without_xdg(XDG_DATA_HOME="/x/data")
        with mock.patch.dict(os.environ, env, clear=True), self.platform(macos=True):
            self.assertEqual(paths.data_home_dirs(), ["/x/data", library])
        with mock.patch.dict(os.environ, env, clear=True), self.platform():
            self.assertEqual(paths.data_home_dirs(), ["/x/data"])

    def test_electron_dirs_add_the_real_mac_location_behind_xdg(self):
        """Electron ignores XDG_CONFIG_HOME on macOS, so a Mac user whose
        dotfiles export it must not lose the IDE lookups entirely."""
        library = os.path.expanduser("~/Library/Application Support")
        env = env_without_xdg(XDG_CONFIG_HOME="/x/config")
        with mock.patch.dict(os.environ, env, clear=True), self.platform(macos=True):
            self.assertEqual(paths.electron_app_data_dirs(), ["/x/config", library])
        with mock.patch.dict(os.environ, env, clear=True), self.platform():
            self.assertEqual(paths.electron_app_data_dirs(), ["/x/config"])
        # Without the variable the two are the same place, named once.
        with mock.patch.dict(os.environ, env_without_xdg(), clear=True), self.platform(macos=True):
            self.assertEqual(paths.electron_app_data_dirs(), [library])

    def test_first_file(self):
        self.assertEqual(paths.first_file([]), "")
        self.assertEqual(paths.first_file(["/nope/a", "/nope/b"]), "/nope/a")
        self.assertEqual(paths.first_file(["/nope/a", __file__]), __file__)


class MacOSProviderPathsTest(IsolatedHomeTest):
    LIBRARY = "Library/Application Support"

    def setUp(self):
        super().setUp()
        os.environ["USER"] = "tester"

    def macos(self, on=True):
        return mock.patch.object(paths, "IS_MACOS", on)

    def _security(self, items):
        def run(argv, **kwargs):
            service = argv[argv.index("-s") + 1]
            result = mock.Mock()
            result.returncode, result.stdout = (0, items[service]) if service in items else (44, "")
            return result

        return mock.patch.object(keychain.subprocess, "run", side_effect=run)

    # ── cursor-agent ────────────────────────────────────────────────────

    def test_cursor_agent_token_comes_from_the_keychain_on_macos(self):
        with self.macos(), self._security({"cursor-access-token": "tok-from-keychain\n"}):
            self.assertEqual(_agent_token(), "tok-from-keychain")

    def test_cursor_agent_keychain_is_not_touched_off_macos(self):
        self.write(".config/cursor/auth.json", '{"accessToken":"tok-from-file"}')
        with self.macos(False), self._security({"cursor-access-token": "tok-from-keychain"}):
            self.assertEqual(_agent_token(), "tok-from-file")

    def test_cursor_agent_falls_back_to_the_dot_cursor_file(self):
        """AGENT_CLI_CREDENTIAL_STORE=file makes the CLI write a file on macOS
        too, next to its identity rather than under the config home."""
        self.write(".cursor/auth.json", '{"accessToken":"tok-from-dotfile"}')
        with self.macos(), self._security({}):
            self.assertEqual(_agent_token(), "tok-from-dotfile")

    def test_cursor_auth_path_overrides_everything(self):
        path = self.write("elsewhere/auth.json", '{"accessToken":"tok-explicit"}')
        os.environ["CURSOR_AUTH_PATH"] = str(path)
        with self.macos(), self._security({"cursor-access-token": "tok-from-keychain"}):
            self.assertEqual(_agent_token(), "tok-explicit")

    def test_cursor_agent_reports_nothing_when_there_is_nothing(self):
        with self.macos(), self._security({}):
            self.assertEqual(_agent_token(), "")

    # ── IDE databases ───────────────────────────────────────────────────

    def test_ide_db_found_under_library_when_xdg_points_elsewhere(self):
        planted = self.write(f"{self.LIBRARY}/Kiro/User/globalStorage/state.vscdb", "")
        with self.macos():
            self.assertEqual(Path(_ide_db()), planted)

    def test_ide_db_prefers_the_xdg_location_when_it_holds_the_file(self):
        planted = self.write(".config/Kiro/User/globalStorage/state.vscdb", "")
        self.write(f"{self.LIBRARY}/Kiro/User/globalStorage/state.vscdb", "")
        with self.macos():
            self.assertEqual(Path(_ide_db()), planted)

    # ── kiro-cli ────────────────────────────────────────────────────────

    def test_kiro_cli_db_under_application_support_on_macos(self):
        """Where a Mac install really is — reached even with XDG_DATA_HOME
        exported, which is the setup that hid it."""
        planted = self.write(f"{self.LIBRARY}/kiro-cli/data.sqlite3", "")
        with self.macos():
            self.assertEqual(Path(_cli_db()), planted)

    def test_kiro_cli_db_stays_xdg_off_macos(self):
        planted = self.write(".local/share/kiro-cli/data.sqlite3", "")
        with self.macos(False):
            self.assertEqual(Path(_cli_db()), planted)

    def test_kiro_cli_db_env_override_wins(self):
        os.environ["KIRO_CLI_DB"] = "/tmp/explicit.sqlite3"
        with self.macos():
            self.assertEqual(_cli_db(), "/tmp/explicit.sqlite3")

    # ── Codex ───────────────────────────────────────────────────────────

    def test_codex_login_read_from_the_keychain_when_there_is_no_file(self):
        """Codex can be configured to keep auth.json's contents in the OS
        keyring instead of on disk."""
        with self.macos(), self._security({"Codex Auth": '{"tokens":{"access_token":"codex-tok"}}'}):
            self.assertEqual(get_openai_credentials()["codexAccessToken"], "codex-tok")

    def test_codex_file_wins_over_the_keychain(self):
        self.write(".codex/auth.json", '{"tokens":{"access_token":"from-file"}}')
        with self.macos(), self._security({"Codex Auth": '{"tokens":{"access_token":"from-keychain"}}'}):
            self.assertEqual(get_openai_credentials()["codexAccessToken"], "from-file")

    def test_codex_keychain_item_is_looked_up_by_service_alone(self):
        """The item is keyed to the codex home in a way this package cannot
        reconstruct, so it must not be narrowed by account."""
        seen = []

        def run(argv, **kwargs):
            seen.append(argv)
            result = mock.Mock()
            result.returncode, result.stdout = 44, ""
            return result

        with self.macos(), mock.patch.object(keychain.subprocess, "run", side_effect=run):
            get_openai_credentials()
        self.assertTrue(seen)
        self.assertNotIn("-a", seen[0])

    # ── Muse ────────────────────────────────────────────────────────────

    def test_muse_key_read_from_the_keychain_on_macos(self):
        """On a Mac the CLI's auth.json carries identity and the Keychain
        carries the secret, so the stored-key lookup alone finds nothing."""
        self.write(".config/muse/auth.json", '{"providers":{"meta":{"email":"a@b.c"}}}')
        with self.macos(), self._security({"ai.meta.dev.credentials": "muse-secret"}):
            self.assertEqual(_muse_api_key(), "muse-secret")

    def test_muse_keychain_item_may_hold_the_whole_document(self):
        with self.macos(), self._security({"ai.meta.dev.credentials": '{"api_key":"muse-json"}'}):
            self.assertEqual(_muse_api_key(), "muse-json")

    def test_muse_stored_key_still_wins_over_the_keychain(self):
        self.write(".config/muse/auth.json", '{"providers":{"meta":{"api_key":"stored"}}}')
        with self.macos(), self._security({"ai.meta.dev.credentials": "muse-secret"}):
            self.assertEqual(_muse_api_key(), "stored")

    def test_muse_environment_key_wins_over_both(self):
        os.environ["META_API_KEY"] = "from-env"
        with self.macos(), self._security({"ai.meta.dev.credentials": "muse-secret"}):
            self.assertEqual(_muse_api_key(), "from-env")

    # ── vendor home directories ─────────────────────────────────────────

    def test_codex_and_grok_homes_follow_their_variables(self):
        self.assertEqual(codex_home(), os.path.expanduser("~/.codex"))
        self.assertEqual(grok_home(), os.path.expanduser("~/.grok"))
        os.environ.update({"CODEX_HOME": "/opt/codex", "GROK_HOME": "~/alt-grok"})
        self.assertEqual(codex_home(), "/opt/codex")
        self.assertEqual(grok_home(), os.path.expanduser("~/alt-grok"))


if __name__ == "__main__":
    unittest.main()
