"""Release manifests must describe the assets we actually ship."""

import ast
import glob
import hashlib
import importlib.util
import json
import os
import re
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

from _support import REPO

SPEC = importlib.util.spec_from_file_location("package_manifests", Path(REPO) / "hosts/windows/package-manifests.py")
manifests = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(manifests)


class PackageManifestsTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.assets = Path(temporary.name)
        self.output = self.assets / "output"
        self.portable = self.assets / "tidesi-windows-3.2.1.zip"
        with zipfile.ZipFile(self.portable, "w") as archive:
            archive.writestr("Tidesi/Tidesi.exe", b"portable executable")
        self.installer = self.assets / "Tidesi-Setup-3.2.1.exe"
        self.installer.write_bytes(b"installer executable")

    def test_scoop_archive_layout_and_hash(self):
        manifests.generate("v3.2.1", self.assets, self.output)
        scoop = json.loads((self.output / "tidesi.json").read_text(encoding="utf-8"))
        self.assertEqual(scoop["version"], "3.2.1")
        asset = scoop["architecture"]["64bit"]
        self.assertEqual(asset["hash"], hashlib.sha256(self.portable.read_bytes()).hexdigest())
        self.assertTrue(asset["url"].endswith("/v3.2.1/tidesi-windows-3.2.1.zip"))
        with zipfile.ZipFile(self.portable) as archive:
            self.assertIn(f"{scoop['extract_dir']}/{scoop['shortcuts'][0][0]}", archive.namelist())
        self.assertEqual(scoop["autoupdate"]["architecture"]["64bit"]["url"].replace("$version", "3.2.1"), asset["url"])

    def test_winget_submission_layout_and_installer_identity(self):
        manifests.generate("3.2.1", self.assets, self.output)
        with zipfile.ZipFile(self.output / "tidesi-winget-3.2.1.zip") as archive:
            self.assertEqual(len(archive.namelist()), 3)
            for name in archive.namelist():
                self.assertTrue(name.startswith("manifests/m/Muddyblack/Tidesi/3.2.1/"))
                self.assertEqual(archive.read(name), (self.output / "winget" / name).read_bytes())
                # winget-pkgs' validation requires the schema URL on the first line.
                text = archive.read(name).decode()
                kind = re.search(r"^ManifestType: (\w+)$", text, re.M).group(1)
                self.assertEqual(
                    text.splitlines()[0],
                    f"# yaml-language-server: $schema=https://aka.ms/winget-manifest.{kind}.1.12.0.schema.json",
                )
            installer = archive.read("manifests/m/Muddyblack/Tidesi/3.2.1/Muddyblack.Tidesi.installer.yaml").decode()
        self.assertIn(hashlib.sha256(self.installer.read_bytes()).hexdigest().upper(), installer)
        self.assertIn("/v3.2.1/Tidesi-Setup-3.2.1.exe", installer)
        self.assertIn("Scope: user", installer)
        self.assertIn("InstallerType: inno", installer)
        inno = (Path(REPO) / "hosts/windows/installer.iss").read_text(encoding="utf-8")
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
            archive.writestr("Tidesi.exe", b"wrong root")
        with self.assertRaisesRegex(ValueError, "must contain"):
            manifests.generate("3.2.1", self.assets, self.output)
        self.assertFalse(self.output.exists())


class WindowsBundleDataTest(unittest.TestCase):
    def test_bundle_contains_every_shared_ui_asset(self):
        spec = Path(REPO) / "hosts/windows/tidesi.spec"
        tree = ast.parse(spec.read_text(encoding="utf-8"))
        statements = []
        for statement in tree.body:
            if isinstance(statement, ast.Assign) and any(isinstance(target, ast.Name) and target.id == "a" for target in statement.targets):
                break
            if not isinstance(statement, (ast.Import, ast.ImportFrom)):
                statements.append(statement)
        scope = {"SPECPATH": str(spec.parent), "os": os, "sys": sys, "glob": glob}
        original_path = sys.path[:]
        try:
            exec(compile(ast.Module(body=statements, type_ignores=[]), str(spec), "exec"), scope)
        finally:
            sys.path[:] = original_path
        bundled = set()
        for source, destination in scope["datas"]:
            source = Path(source)
            if source.is_dir():
                bundled.update((Path(destination) / path.relative_to(source)).as_posix() for path in source.rglob("*") if path.is_file())
            else:
                bundled.add((Path(destination) / source.name).as_posix())
        for path in (Path(REPO) / "ui").rglob("*"):
            if path.is_file():
                self.assertIn(path.relative_to(REPO).as_posix(), bundled)
