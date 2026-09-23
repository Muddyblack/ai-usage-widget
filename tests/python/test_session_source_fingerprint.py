import hashlib
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from aiusage import session_manifest


class SourceFingerprintTest(unittest.TestCase):
    def test_unchanged_source_has_the_same_normalized_fingerprint(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "rollout.jsonl"
            source.write_text("one", encoding="utf-8")
            first = session_manifest.source_fingerprint(str(source), 10, 3)
            second = session_manifest.source_fingerprint(str(root / "." / source.name), 10, 3)

        self.assertEqual(first, second)
        self.assertEqual(first.source_id, hashlib.sha256(os.fsencode(os.path.realpath(source))).hexdigest())

    def test_one_changed_file_changes_only_its_source_fingerprint(self):
        first = session_manifest.source_fingerprint("/tmp/codex-a/rollout.jsonl", 1, 3)
        unchanged = session_manifest.source_fingerprint("/tmp/codex-b/rollout.jsonl", 5, 6)
        changed = session_manifest.source_fingerprint("/tmp/codex-a/rollout.jsonl", 3, 3)

        self.assertNotEqual(first.fingerprint, changed.fingerprint)
        self.assertNotEqual(unchanged.fingerprint, changed.fingerprint)
        self.assertEqual(unchanged, session_manifest.source_fingerprint("/tmp/codex-b/rollout.jsonl", 5, 6))

    def test_different_codex_homes_have_isolated_source_ids(self):
        with tempfile.TemporaryDirectory() as directory:
            first_home = Path(directory) / "first"
            second_home = Path(directory) / "second"
            first_home.mkdir()
            second_home.mkdir()
            first = session_manifest.source_fingerprint(str(first_home / "sessions"), 1, 2)
            second = session_manifest.source_fingerprint(str(second_home / "sessions"), 1, 2)

        self.assertNotEqual(first.source_id, second.source_id)
        self.assertNotEqual(first.fingerprint, second.fingerprint)

    def test_source_fingerprint_keeps_full_digest_when_short_prefix_collides(self):
        original_sha256 = hashlib.sha256

        def colliding_prefix(value=b""):
            real = original_sha256(value)

            class Digest:
                def hexdigest(self):
                    return "0" * 16 + real.hexdigest()[16:]

            return Digest()

        with mock.patch.object(session_manifest.hashlib, "sha256", side_effect=colliding_prefix):
            first = session_manifest.source_fingerprint("/private/rollout.jsonl", 42, 7)
            changed = session_manifest.source_fingerprint("/private/rollout.jsonl", 42, 8)

        self.assertEqual(first.source_id[:16], changed.source_id[:16])
        self.assertNotEqual(first.fingerprint, changed.fingerprint)
        self.assertEqual(len(first.fingerprint), 64)


if __name__ == "__main__":
    unittest.main()
