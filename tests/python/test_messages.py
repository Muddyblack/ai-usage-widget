"""Translatable backend text: a Msg is the English string everywhere, and the
envelope carries its template beside it for the frontends to translate."""

import json
import pickle
import unittest

import _support  # noqa: F401  (puts the backend on sys.path)
from aiusage.contract import finalize, provider_error
from aiusage.messages import Msg, lines, tr


class MessageTest(unittest.TestCase):
    def test_a_message_is_its_english_text(self):
        m = tr("%1 / %2 tokens", 120, 500)
        self.assertIsInstance(m, str)
        self.assertEqual(m, "120 / 500 tokens")
        self.assertEqual(m.i18n(), {"id": "%1 / %2 tokens", "args": ["120", "500"]})
        self.assertEqual(json.dumps({"d": m}), '{"d": "120 / 500 tokens"}')

    def test_unknown_placeholders_are_left_alone(self):
        self.assertEqual(tr("%1 and %3", "a"), "a and %3")

    def test_survives_copies(self):
        m = tr("Plan: %1", "pro")
        clone = pickle.loads(pickle.dumps(m))
        self.assertIsInstance(clone, Msg)
        self.assertEqual(clone.i18n(), m.i18n())

    def test_finalize_writes_the_template_beside_the_text(self):
        out = finalize({"label": tr("5-hour session"), "detail": "plain", "rows": [{"note": tr("Plan: %1", "max")}]})
        self.assertEqual(out["label"], "5-hour session")
        self.assertEqual(out["labelI18n"], {"id": "5-hour session", "args": []})
        self.assertNotIn("detailI18n", out)
        self.assertEqual(out["rows"][0]["noteI18n"], {"id": "Plan: %1", "args": ["max"]})
        self.assertIs(type(out["label"]), str)

    def test_lines_translate_line_by_line(self):
        tooltip = lines("Cursor", "", tr("Included usage: %1%", 40))
        self.assertEqual(tooltip, "Cursor\nIncluded usage: 40%")
        out = finalize({"tooltip": tooltip})
        self.assertEqual(
            out["tooltipI18n"],
            {"lines": [{"id": "Cursor", "args": [], "plain": True}, {"id": "Included usage: %1%", "args": ["40"]}]},
        )

    def test_an_error_row_is_translatable(self):
        row = finalize(provider_error("claude", "Claude", "#cc785c", 0, tr("Claude not logged in"), {}))
        self.assertEqual(row["errorI18n"]["id"], "Claude not logged in")
        self.assertEqual(row["summary"]["textI18n"]["id"], "unavailable")
        self.assertEqual(row["slots"][0]["tooltipI18n"]["id"], "Claude not logged in")


if __name__ == "__main__":
    unittest.main()
