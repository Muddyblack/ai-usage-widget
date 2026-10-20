"""The Homebrew cask must point at the DMGs the release actually ships."""

import importlib.util
import re
import unittest
from pathlib import Path

from _support import REPO

SPEC = importlib.util.spec_from_file_location("homebrew_cask", Path(REPO) / "hosts/macos/homebrew-cask.py")
homebrew = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(homebrew)

ARM = "a" * 64
INTEL = "b" * 64


class HomebrewCaskTest(unittest.TestCase):
    def test_version_and_hashes_per_architecture(self):
        text = homebrew.cask("v4.0.0", ARM, INTEL)
        self.assertIn('version "4.0.0"', text)
        self.assertIn(f'arm:   "{ARM}"', text)
        self.assertIn(f'intel: "{INTEL}"', text)
        self.assertIn('app "Tidesi.app"', text)

    def test_url_matches_the_release_asset_names(self):
        # Resolve the cask's interpolation the way Homebrew does and compare
        # with the names release.yml advertises.
        text = homebrew.cask("4.0.0", ARM, INTEL)
        template = re.search(r'^  url "([^"]+)"', text, re.M).group(1)
        release = (Path(REPO) / ".github/workflows/release.yml").read_text(encoding="utf-8")
        for arch in ("apple-silicon", "intel"):
            url = template.replace("#{version}", "4.0.0").replace("#{arch}", arch)
            self.assertTrue(url.endswith(f"/v4.0.0/tidesi-macos-4.0.0-{arch}.dmg"))
            self.assertIn(f"tidesi-macos-${{{{ steps.info.outputs.version }}}}-{arch}.dmg", release)

    def test_rejects_prereleases_and_bad_hashes(self):
        with self.assertRaises(ValueError):
            homebrew.cask("4.1.0-rc1", ARM, INTEL)
        with self.assertRaises(ValueError):
            homebrew.cask("4.0.0", "sha256:" + ARM, INTEL)


if __name__ == "__main__":
    unittest.main()
