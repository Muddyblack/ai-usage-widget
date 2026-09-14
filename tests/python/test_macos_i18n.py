"""The macOS app's strings, against the catalogs every frontend shares.

The Swift app reads translate/<lang>.po rather than carrying a .lproj of its
own, which only works while three things hold: its msgids are plain literals
xgettext can extract, they are spelled exactly as the QML frontends spell them,
and Messages.sh actually looks at macos/. None of that is visible from reading
the Swift, and all of it fails silently — an unextractable string is simply
never offered to a translator, and a misspelt one is simply never translated.
"""

import os
import re
import unittest

from _support import REPO

SWIFT_ROOT = os.path.join(REPO, "macos", "Sources", "AIUsage")
MESSAGES_SH = os.path.join(REPO, "translate", "Messages.sh")
BUILD_SH = os.path.join(REPO, "macos", "scripts", "build-app.sh")
FRENCH = os.path.join(REPO, "translate", "fr.po")

# i18n("…"), i18nNoop("…") and the first literal of i18nc/i18np.
CALL = re.compile(r'\bi18n(?:c|p|Noop)?\(\s*"((?:[^"\\]|\\.)*)"')
# Any call with something other than a literal first argument.
INDIRECT = re.compile(r'\bi18n(?:c|p|Noop)?\(\s*(?!")')


def swift_files():
    for root, _dirs, files in os.walk(SWIFT_ROOT):
        for name in sorted(files):
            if name.endswith(".swift"):
                yield os.path.join(root, name)


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def without_comments(text):
    """Swift with its comments blanked out.

    xgettext does not extract from a comment, and this module must not either —
    the doc comment on i18n() itself contains a call that looks exactly like a
    real one.
    """
    out = []
    i, n = 0, len(text)
    in_string = in_line = False
    block = 0
    while i < n:
        c = text[i]
        if in_line:
            if c == "\n":
                in_line = False
                out.append(c)
            else:
                out.append(" ")
            i += 1
        elif block:
            if text.startswith("*/", i):
                block -= 1
                out.append("  ")
                i += 2
                continue
            if text.startswith("/*", i):
                block += 1
                out.append("  ")
                i += 2
                continue
            out.append("\n" if c == "\n" else " ")
            i += 1
        elif in_string:
            if c == "\\" and i + 1 < n:
                out.append(text[i : i + 2])
                i += 2
                continue
            if c == '"':
                in_string = False
            out.append(c)
            i += 1
        elif text.startswith("//", i):
            in_line = True
        elif text.startswith("/*", i):
            block = 1
            out.append("  ")
            i += 2
        else:
            if c == '"':
                in_string = True
            out.append(c)
            i += 1
    return "".join(out)


class SwiftStringsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not os.path.isdir(SWIFT_ROOT):
            raise unittest.SkipTest("macos/ is not checked out")
        cls.sources = {path: without_comments(read(path)) for path in swift_files()}

    def msgids(self):
        found = set()
        for text in self.sources.values():
            found.update(CALL.findall(text))
        found.discard("")
        return found

    def test_no_msgid_uses_swift_interpolation(self):
        """`i18n("Resets in \\(x)")` would put the value *inside* the msgid, so
        every distinct countdown would be its own untranslatable entry — and
        xgettext's C parser, which is what reads these, would not see it as one
        string at all. ki18n's %1 is the placeholder."""
        offenders = []
        for path, text in self.sources.items():
            for msgid in CALL.findall(text):
                if "\\(" in msgid:
                    offenders.append(f"{os.path.relpath(path, REPO)}: {msgid}")
        self.assertFalse(offenders, "interpolation inside a msgid:\n  " + "\n  ".join(offenders))

    def test_every_translation_call_takes_a_literal_or_is_a_known_indirection(self):
        """xgettext can only extract a literal. The one exception is the
        settings page's key-field table, whose strings are marked with
        i18nNoop() where the table is built."""
        # The declarations of the functions themselves, and the settings
        # page's key-field table, whose strings are marked where it is built.
        allowed = {"i18n(field.label)", "i18n(field.help)"}
        offenders = []
        for path, text in self.sources.items():
            for match in INDIRECT.finditer(text):
                line_start = text.rfind("\n", 0, match.start()) + 1
                if text[line_start : match.start()].lstrip().startswith("func "):
                    continue  # the declaration, not a call
                snippet = text[match.start() : match.start() + 40].split(")")[0] + ")"
                if snippet.strip() not in allowed:
                    offenders.append(f"{os.path.relpath(path, REPO)}: {snippet.strip()}")
        self.assertFalse(offenders, "non-literal msgid:\n  " + "\n  ".join(offenders))

    def test_nothing_still_goes_through_the_apple_catalog(self):
        """String(localized:) reads a .lproj this app deliberately does not
        have, so it would silently never translate."""
        for path, text in self.sources.items():
            with self.subTest(file=os.path.basename(path)):
                self.assertNotIn("String(localized:", text)

    def test_no_bare_literal_is_shown_to_the_user(self):
        """A `Text("…")` that skipped i18n() is a string no translator sees."""
        offenders = []
        for path, text in self.sources.items():
            for match in re.finditer(r'Text\("((?:[^"\\]|\\.)*)"\)', text):
                offenders.append(f"{os.path.relpath(path, REPO)}: {match.group(1)}")
        self.assertFalse(offenders, "untranslated Text():\n  " + "\n  ".join(offenders))

    def test_placeholders_are_numbered_from_one_and_contiguous(self):
        """%2 with no %1 is a translator trap: the substitution leaves it in
        place and the string ships with a literal "%2" in it."""
        for msgid in self.msgids():
            positions = sorted({int(d) for d in re.findall(r"%(\d)", msgid)})
            if positions:
                with self.subTest(msgid=msgid):
                    self.assertEqual(positions, list(range(1, len(positions) + 1)))

    # ── Against the catalog ─────────────────────────────────────────────

    def test_the_strings_shared_with_the_qml_frontends_are_spelled_identically(self):
        """The whole reason for reading the shared catalog: a string the QML
        frontends have translated should be translated here the moment it is
        used. A near-miss spelling silently loses that."""
        if not os.path.isfile(FRENCH):
            self.skipTest("no French catalog")
        catalog = set(re.findall(r'^msgid "((?:[^"\\]|\\.)*)"$', read(FRENCH), re.MULTILINE))
        shared = self.msgids() & catalog
        # Not a threshold for its own sake: these are the strings that prove the
        # sharing works at all.
        for expected in ("Settings", "Refresh", "Providers", "Language", "Resets in %1", "just now"):
            with self.subTest(msgid=expected):
                self.assertIn(expected, self.msgids(), "the Swift app no longer uses this msgid")
                self.assertIn(expected, catalog, "the catalog no longer carries this msgid")
        self.assertGreaterEqual(len(shared), 6)


class ExtractionTest(unittest.TestCase):
    """Messages.sh and build-app.sh, which carry the strings to and from the app."""

    @classmethod
    def setUpClass(cls):
        if not os.path.isfile(MESSAGES_SH):
            raise unittest.SkipTest("translate/Messages.sh is missing")
        cls.messages = read(MESSAGES_SH)

    def test_the_swift_sources_are_extracted(self):
        self.assertIn("macos/Sources", self.messages)
        self.assertIn("--language=C", self.messages, "xgettext has no Swift backend")
        self.assertIn("msgcat", self.messages, "the two passes have to be merged into one catalog")

    def test_every_call_shape_the_swift_uses_is_a_keyword(self):
        swift = "".join(read(path) for path in swift_files())
        for name in ("i18n", "i18nc", "i18np", "i18nNoop"):
            if re.search(rf"\b{name}\(", swift):
                with self.subTest(keyword=name):
                    self.assertRegex(self.messages, rf"--keyword={name}\b")

    def test_the_catalogs_are_copied_into_the_app(self):
        """The app parses translate/*.po at runtime, so they have to be in the
        bundle — a built .app is not run from the checkout."""
        if not os.path.isfile(BUILD_SH):
            self.skipTest("no build script")
        build = read(BUILD_SH)
        self.assertRegex(build, r'cp "\$ROOT"/translate/\*\.po')
        self.assertIn("Contents/Resources/translate", build)

        catalog_swift = read(os.path.join(SWIFT_ROOT, "Support", "Catalog.swift"))
        self.assertIn("Contents/Resources/translate", catalog_swift)


if __name__ == "__main__":
    unittest.main()
