"""Release manifests must describe the assets we actually ship."""

import hashlib
import importlib.util
import json
import tempfile
import unittest
import zipfile
from pathlib import Path

from _support import REPO

SPEC = importlib.util.spec_from_file_location("package_manifests", Path(REPO) / "windows/package-manifests.py")
manifests = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(manifests)


class PackageManifestsTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.assets = Path(temporary.name)
        self.output = self.assets / "output"
        self.portable = self.assets / "ai-usage-windows-3.2.1.zip"
        with zipfile.ZipFile(self.portable, "w") as archive:
            archive.writestr("AI Usage/AI Usage.exe", b"portable executable")
        self.installer = self.assets / "AI-Usage-Setup-3.2.1.exe"
        self.installer.write_bytes(b"installer executable")

    def test_scoop_archive_layout_and_hash(self):
        manifests.generate("v3.2.1", self.assets, self.output)
        scoop = json.loads((self.output / "ai-usage.json").read_text(encoding="utf-8"))
        self.assertEqual(scoop["version"], "3.2.1")
        asset = scoop["architecture"]["64bit"]
        self.assertEqual(asset["hash"], hashlib.sha256(self.portable.read_bytes()).hexdigest())
        self.assertTrue(asset["url"].endswith("/v3.2.1/ai-usage-windows-3.2.1.zip"))
        with zipfile.ZipFile(self.portable) as archive:
            self.assertIn(f"{scoop['extract_dir']}/{scoop['shortcuts'][0][0]}", archive.namelist())
        self.assertEqual(scoop["autoupdate"]["architecture"]["64bit"]["url"].replace("$version", "3.2.1"), asset["url"])

    def test_winget_submission_layout_and_installer_identity(self):
        manifests.generate("3.2.1", self.assets, self.output)
        with zipfile.ZipFile(self.output / "ai-usage-winget-3.2.1.zip") as archive:
            self.assertEqual(len(archive.namelist()), 3)
            for name in archive.namelist():
                self.assertTrue(name.startswith("manifests/m/Muddyblack/AIUsage/3.2.1/"))
                self.assertEqual(archive.read(name), (self.output / "winget" / name).read_bytes())
            installer = archive.read("manifests/m/Muddyblack/AIUsage/3.2.1/Muddyblack.AIUsage.installer.yaml").decode()
        self.assertIn(hashlib.sha256(self.installer.read_bytes()).hexdigest().upper(), installer)
        self.assertIn("/v3.2.1/AI-Usage-Setup-3.2.1.exe", installer)
        self.assertIn("Scope: user", installer)
        self.assertIn("InstallerType: inno", installer)
        inno = (Path(REPO) / "windows/installer.iss").read_text(encoding="utf-8")
        self.assertIn(f"AppId={{{manifests.PRODUCT_CODE.removesuffix('_is1')}", inno)

    def test_rejects_non_release_versions_before_writing(self):
        for version in ("", "../3.2.1", "3.2.1-rc1", "0.0.0-ci", "v3.2.1\n"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                manifests.generate(version, self.assets, self.output)
        self.assertFalse(self.output.exists())

    def test_missing_installer_does_not_emit_partial_manifests(self):
        self.installer.unlink()
        with self.assertRaises(FileNotFoundError):
            manifests.generate("3.2.1", self.assets, self.output)
        self.assertFalse(self.output.exists())

    def test_wrong_archive_layout_is_rejected(self):
        with zipfile.ZipFile(self.portable, "w") as archive:
            archive.writestr("AI Usage.exe", b"wrong root")
        with self.assertRaisesRegex(ValueError, "must contain"):
            manifests.generate("3.2.1", self.assets, self.output)
        self.assertFalse(self.output.exists())
