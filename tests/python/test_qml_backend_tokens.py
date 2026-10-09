"""Session text in the shared UI is untrusted local file content."""

import os
import re
import unittest

import _support


class QmlBackendTokensTest(unittest.TestCase):
    def test_session_content_cannot_enable_rich_text_image_requests(self):
        # Session titles and details are untrusted local file content. Qt's
        # automatic rich text detection can fetch images without a click.
        for relative in ("ui/SessionsPage.qml",):
            with self.subTest(frontend=relative):
                with open(os.path.join(_support.REPO, relative), encoding="utf-8") as stream:
                    source = stream.read()
                bindings = re.findall(r"text: [^\n]*modelData\.(?:title|sessionName|detail)[^\n]*\n([^{}]*)", source)
                self.assertEqual(len(bindings), 3)
                for properties in bindings:
                    self.assertRegex(properties, r"textFormat:\s*Text\.PlainText\b")


if __name__ == "__main__":
    unittest.main()
