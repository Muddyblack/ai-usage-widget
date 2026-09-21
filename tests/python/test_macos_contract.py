"""The Swift frontend's model against the envelope the backend really emits.

macos/ reads the same JSON contract as every other frontend, but it is the one
frontend that cannot be compiled — let alone run — on a Linux machine, so a
field renamed in the backend would otherwise go unnoticed there until someone
with a Mac happened to build it.

These read Contract.swift as text and check the names in it against a real
finalized envelope. That is a shallow check by design: it cannot say the Swift
is correct, only that the two halves still agree on what the fields are called,
which is the mistake that would otherwise be silent.
"""

import os
import re
import unittest

from _support import REPO, fixture, provider_fixtures

CONTRACT_SWIFT = os.path.join(REPO, "macos", "Sources", "AIUsage", "Backend", "Contract.swift")
SESSIONS_VIEW_SWIFT = os.path.join(REPO, "macos", "Sources", "AIUsage", "Views", "SessionsView.swift")
APP_MODEL_SWIFT = os.path.join(REPO, "macos", "Sources", "AIUsage", "App", "AppModel.swift")

# Sub-objects Contract.swift decodes out of `details`, which is a free-form
# blob in the contract — so they are checked against the fixtures separately.
#
# Every one of these has to be *shared*: a key only one provider fills would be
# per-provider logic in a frontend whose whole claim is that it has none, and
# adding a provider would then mean adding Swift. `stats` qualifies because
# five providers fill the same fields.
DETAIL_KEYS = {"status", "currency", "quotaError", "stats"}


def declaration(text, name):
    """One top-level `struct`/`enum` body, up to the next top-level declaration.

    Several types in this file declare a `CodingKeys`, so a search for one has
    to be told whose."""
    match = re.search(rf"^(?:struct|enum) {name}\b", text, re.MULTILINE)
    if not match:
        raise AssertionError(f"no top-level `{name}` in Contract.swift")
    rest = text[match.end() :]
    end = re.search(r"^(?:struct|enum|extension) \w", rest, re.MULTILINE)
    return rest[: end.start()] if end else rest


def coding_keys(text, type_name, enum_name="CodingKeys"):
    """The cases of one type's `enum … CodingKey` declaration, as a set."""
    body = declaration(text, type_name)
    match = re.search(rf"enum {enum_name}: String, CodingKey {{(.+?)}}", body, re.DOTALL)
    if not match:
        raise AssertionError(f"no `enum {enum_name}` inside {type_name}")
    names = set()
    for line in match.group(1).splitlines():
        line = line.strip()
        if not line.startswith("case "):
            continue
        names.update(part.strip() for part in line[len("case ") :].split(","))
    return {name for name in names if name}


class SwiftContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not os.path.isfile(CONTRACT_SWIFT):
            raise unittest.SkipTest("macos/ is not checked out")
        with open(CONTRACT_SWIFT, encoding="utf-8") as fh:
            cls.text = fh.read()
        cls.provider = fixture("claude-success")
        # Optional fields — quotaWindows.note, a provider's chartWindows — are
        # absent from most fixtures, so the field names are gathered across all
        # of them rather than from whichever one is convenient.
        cls.emitted = cls._emitted_fields()
        with open(SESSIONS_VIEW_SWIFT, encoding="utf-8") as fh:
            cls.sessions_view = fh.read()
        with open(APP_MODEL_SWIFT, encoding="utf-8") as fh:
            cls.app_model = fh.read()

    @classmethod
    def _emitted_fields(cls):
        seen = {name: set() for name in ("provider", "summary", "quotaWindows", "slots", "chartWindows", "status")}
        for name in provider_fixtures():
            try:
                provider = fixture(name)
            except (ValueError, KeyError):
                continue
            seen["provider"].update(provider)
            seen["summary"].update(provider.get("summary") or {})
            seen["status"].update((provider.get("details") or {}).get("status") or {})
            for key in ("quotaWindows", "slots", "chartWindows"):
                for row in provider.get(key) or []:
                    seen[key].update(row)
        return seen

    def assert_decodes(self, type_name, sample):
        """Every field `type_name` decodes is one the backend really emits."""
        keys = coding_keys(self.text, type_name)
        unknown = keys - set(sample)
        self.assertFalse(
            unknown,
            f"{type_name} decodes {sorted(unknown)}, which the backend does not emit — it emits {sorted(sample)}",
        )

    def test_envelope_fields(self):
        self.assert_decodes("Envelope", {"schemaVersion": 1, "updatedAt": 0, "active": "", "providers": [], "localSpend": {}})

    def test_provider_fields(self):
        self.assert_decodes("Provider", self.emitted["provider"])

    def test_detail_fields_that_are_read(self):
        """`details` is per-provider and mostly the Plasma widget's business.
        The Swift app reads only the shared sub-objects out of it."""
        self.assertEqual(coding_keys(self.text, "Provider", "DetailKeys"), DETAIL_KEYS)
        details = self.provider.get("details") or {}
        self.assertIn("status", details, "every provider carries details.status")

    def test_every_detail_key_it_reads_is_one_several_providers_fill(self):
        """The rule behind DETAIL_KEYS, checked rather than asserted in a
        comment: a key only one provider sends is that provider's business and
        does not belong in a frontend that claims to know none of them."""
        counts = dict.fromkeys(DETAIL_KEYS, 0)
        for name in provider_fixtures():
            try:
                details = fixture(name).get("details") or {}
            except (ValueError, KeyError):
                continue
            for key in DETAIL_KEYS:
                if key in details:
                    counts[key] += 1
        for key, count in counts.items():
            with self.subTest(key=key):
                self.assertGreater(count, 1, f"details.{key} is filled by only {count} fixture(s)")

    def test_activity_stats_fields(self):
        """The stats block, gathered across every provider that reports one."""
        seen = set()
        for name in provider_fixtures():
            try:
                stats = (fixture(name).get("details") or {}).get("stats") or {}
            except (ValueError, KeyError):
                continue
            if stats.get("available"):
                seen.update(stats)
        self.assertTrue(seen, "no fixture reports activity stats")
        self.assert_decodes("ActivityStats", seen)

    def test_sub_object_fields(self):
        for type_name, key in (
            ("Summary", "summary"),
            ("QuotaWindow", "quotaWindows"),
            ("Slot", "slots"),
            ("ChartWindow", "chartWindows"),
            ("ServiceStatus", "status"),
        ):
            with self.subTest(type=type_name):
                self.assertTrue(self.emitted[key], f"no fixture carries a {key} row")
                self.assert_decodes(type_name, self.emitted[key])

    def test_every_field_the_backend_emits_is_named(self):
        """The other direction: a field added to the contract should be a
        decision here, not an oversight."""
        decoded = coding_keys(self.text, "Provider")
        missing = self.emitted["provider"] - decoded
        self.assertFalse(
            missing,
            f"the backend emits {sorted(missing)}, which Contract.swift does not name — "
            "add it, or say in the file's doc comment why the Mac app ignores it",
        )

    def test_the_quota_window_note_is_carried(self):
        """`note` is what a row with no meter says beside its value, and a
        frontend that drops it loses the context and nothing else — which is
        exactly the kind of omission that goes unnoticed."""
        self.assertIn("note", coding_keys(self.text, "QuotaWindow"))
        self.assertIn("note", self.emitted["quotaWindows"], "no fixture exercises quotaWindows.note")

    def test_the_menu_bar_reads_the_same_severity_thresholds_as_the_panel_pill(self):
        """70 % amber, 90 % red — windows/app.py:_text_colour and
        hyprland/PanelSlot.qml. A glance has to mean the same thing on every
        platform, so the numbers are checked rather than trusted to a comment."""
        for path in (
            os.path.join(REPO, "macos", "Sources", "AIUsage", "MenuBar", "MenuBarTitle.swift"),
            os.path.join(REPO, "macos", "Sources", "AIUsage", "Views", "Theme.swift"),
        ):
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
            with self.subTest(file=os.path.basename(path)):
                self.assertIn(">= 90", text)
                self.assertIn(">= 70", text)

    def test_the_provider_list_matches_the_backend(self):
        """SettingsStore lists the providers so the settings window can show a
        row for one the backend has not reported yet."""
        from aiusage import config

        path = os.path.join(REPO, "macos", "Sources", "AIUsage", "Backend", "SettingsStore.swift")
        with open(path, encoding="utf-8") as fh:
            text = fh.read()

        listed = re.search(r"static let allProviders = \[(.+?)\]", text, re.DOTALL)
        self.assertIsNotNone(listed, "no allProviders list in SettingsStore.swift")
        self.assertEqual(re.findall(r'"([a-z]+)"', listed.group(1)), config.ALL_PROVIDERS)

        opt_in = re.search(r"static let optInProviders: Set<String> = \[(.+?)\]", text, re.DOTALL)
        self.assertIsNotNone(opt_in, "no optInProviders set in SettingsStore.swift")
        self.assertEqual(set(re.findall(r'"([a-z]+)"', opt_in.group(1))), config.OPT_IN_PROVIDERS)

    def test_the_history_payload_is_passed_the_way_both_launchers_read_it(self):
        """`history-io` takes the samples in $WIDGET_HISTORY_JSON.

        The frozen backend would also take them on stdin, but the checkout's
        bash launcher only reads the variable — and the Swift app runs whichever
        of the two it finds. Passing them the other way fails silently: the
        command succeeds and saves nothing."""
        runner = os.path.join(REPO, "macos", "Sources", "AIUsage", "Backend", "BackendRunner.swift")
        with open(runner, encoding="utf-8") as fh:
            swift = fh.read()
        for path in (
            runner,
            os.path.join(REPO, "package", "contents", "tools", "sh", "history-io"),
            os.path.join(REPO, "package", "contents", "tools", "aiusage", "historyio.py"),
        ):
            with open(path, encoding="utf-8") as fh:
                with self.subTest(file=os.path.basename(path)):
                    self.assertIn("WIDGET_HISTORY_JSON", fh.read())
        self.assertNotIn("--stdin", swift, "the bash launcher ignores --stdin, so a save through it would be a silent no-op")

    def test_the_settings_key_names_match_the_backend_exports(self):
        """A key pasted in the Mac settings window has to land under the name
        the backend exports to WIDGET_*, or it is silently ignored."""
        from aiusage import config

        path = os.path.join(REPO, "macos", "Sources", "AIUsage", "Views", "SettingsView.swift")
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        block = re.search(r"keyFields: \[String: \(key: String.+?\n    \]", text, re.DOTALL)
        self.assertIsNotNone(block, "no keyFields table in SettingsView.swift")
        used = set(re.findall(r'\(\s*"([A-Za-z]+)",', block.group(0)))
        known = {name for _var, name in config._KEY_EXPORTS}
        self.assertLessEqual(used, known, f"unknown settings keys: {sorted(used - known)}")

    def test_sessions_refresh_button_preserves_the_active_filter(self):
        self.assertRegex(
            self.sessions_view,
            r"Button\s*\{\s*model\.refreshSessions\(query:\s*filterText\)\s*\}\s*label",
        )

    def test_session_filter_changes_are_debounced_before_refreshing(self):
        self.assertRegex(
            self.sessions_view,
            r"\.onChange\(of: filterText\)\s*\{\s*model\.scheduleSessionsRefresh\(query:\s*\$0\)\s*\}",
        )
        self.assertNotRegex(
            self.sessions_view,
            r"\.onChange\(of: filterText\).*model\.refreshSessions\(query:\s*\$0\)",
        )

    def test_local_session_decodes_full_title(self):
        self.assertIn("fullTitle", declaration(self.text, "LocalSession"))

    def test_sessions_view_expands_full_title_on_tap(self):
        self.assertIn("fullTitle", self.sessions_view)

    def test_session_refresh_scheduler_replaces_pending_work_after_300_ms(self):
        self.assertRegex(self.app_model, r"func scheduleSessionsRefresh\(query: String\)")
        self.assertRegex(self.app_model, r"sessionsDebounceTask\?\.cancel\(\)")
        self.assertRegex(self.app_model, r"sessionsDebounceTask\s*=\s*Task\s*\{")
        self.assertRegex(self.app_model, r"Task\.sleep\(for:\s*\.milliseconds\(300\)\)")

    def test_local_sessions_decodes_pagination_metadata_leniently(self):
        body = declaration(self.text, "LocalSessions")
        for field in ("total", "offset", "limit", "hasMore", "totalExact"):
            self.assertIn(field, coding_keys(self.text, "LocalSessions"))
            self.assertRegex(body, rf"try\?\s+c\.decode(?:IfPresent)?\([^)]*,\s*forKey:\s*\.{field}\)")

    def test_app_model_owns_session_pagination_state(self):
        for field in ("sessionsTotal", "sessionsOffset", "sessionsLimit", "sessionsHasMore", "sessionsTotalExact"):
            self.assertRegex(self.app_model, rf"\b(?:private\(set\)\s+)?var\s+{field}\b")
        self.assertRegex(self.app_model, r"\b(?:private\s+)?let\s+sessionsLimit\s*=\s*60\b")

    def test_app_model_exposes_load_more_for_all_session_searches(self):
        match = re.search(r"func loadMoreSessions\(\)\s*\{(.+?)\n    \}", self.app_model, re.DOTALL)
        self.assertIsNotNone(match, "AppModel has no loadMoreSessions action")
        body = match.group(1)
        self.assertRegex(body, r"sessionsHasMore")
        self.assertNotRegex(body, r"sessionsQuery\.isEmpty")
        self.assertRegex(body, r"sessionsOffset.*sessionsLimit|sessionsLimit.*sessionsOffset")
        self.assertRegex(body, r"refreshSessions")

    def test_app_model_requests_every_session_search_in_sixty_row_pages(self):
        self.assertRegex(self.app_model, r"let requestedLimit: Int\? = 60")
        self.assertNotRegex(self.app_model, r"query\.isEmpty\s*\?\s*60\s*:\s*nil")
        self.assertNotRegex(self.app_model, r"query\.isEmpty\s*\?\s*requestedOffset\s*:\s*nil")
        self.assertRegex(
            self.app_model,
            r"Backend\.sessions\(\s*query,\s*limit:\s*requestedLimit,\s*offset:\s*requestedOffset",
        )

    def test_sessions_view_uses_total_and_routes_load_more(self):
        self.assertRegex(self.sessions_view, r"Text\([^\n]*model\.sessionsTotal")
        self.assertNotRegex(self.sessions_view, r"Text\([^\n]*model\.localSessions\.count")
        match = re.search(
            r"if\s+model\.sessionsHasMore\s*\{(.+?)\n\s*\}",
            self.sessions_view,
            re.DOTALL,
        )
        self.assertIsNotNone(match, "SessionsView does not gate load-more on hasMore")
        self.assertRegex(match.group(1), r"model\.loadMoreSessions\(\)")


if __name__ == "__main__":
    unittest.main()
