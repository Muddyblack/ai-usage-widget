"""The Plasma QML translates a few backend strings by matching their exact
English text. If the backend rewords one, the QML silently falls back to
English, so pin both ends to the same literal."""

import json
import os
import re
import unittest

import _support
from aiusage.providers import grok, kimi_code

MAIN_QML = os.path.join(_support.REPO, "package", "contents", "ui", "main.qml")


def main_qml():
    with open(MAIN_QML, encoding="utf-8") as f:
        return f.read()


class QmlBackendTokensTest(unittest.TestCase):
    def test_session_content_cannot_enable_rich_text_image_requests(self):
        # Session titles and details are untrusted local file content. Qt's
        # automatic rich text detection can fetch images without a click.
        for relative in ("package/contents/ui/SessionsTab.qml", "hyprland/SessionsPage.qml"):
            with self.subTest(frontend=relative):
                with open(os.path.join(_support.REPO, relative), encoding="utf-8") as stream:
                    source = stream.read()
                bindings = re.findall(r"text: [^\n]*modelData\.(?:title|sessionName|detail)[^\n]*\n([^{}]*)", source)
                self.assertEqual(len(bindings), 3)
                for properties in bindings:
                    self.assertRegex(properties, r"textFormat:\s*Text\.PlainText\b")

    def test_kimi_plan_used_up_fallback(self):
        body = json.dumps({"code": "resource_exhausted", "details": [{"debug": {"reason": "REASON_QUOTA_EXCEEDED"}}]})
        message = kimi_code.parse_usage_response(429, body)["message"]
        self.assertIn(f'root.kimiPlanMessage === "{message}"', main_qml())

    def test_grok_free_tier_window(self):
        args = dict.fromkeys(grok._assemble.__code__.co_varnames[: grok._assemble.__code__.co_argcount], "")
        args.update(local={}, credits={}, billing={}, local_billing={}, free_usage={"limit": 10, "used": 1}, team_blocked=False, blocked_reasons=[])
        window = grok._assemble(**args)["quotaWindow"]
        self.assertIn(f'root.grokQuotaWindow === "{window}"', main_qml())


if __name__ == "__main__":
    unittest.main()
