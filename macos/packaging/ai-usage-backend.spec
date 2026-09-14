# -*- mode: python ; coding: utf-8 -*-
#
# The frozen backend that ships inside AI Usage.app. One directory, not one
# file: a --onefile build unpacks itself to a temporary directory on every
# single run, which for a program the app starts every poll is both slow and a
# steady stream of writes.

import os

# SPECPATH is this file's own directory, whatever PyInstaller was run from.
ROOT = os.path.abspath(os.path.join(SPECPATH, "..", ".."))  # noqa: F821
TOOLS = os.path.join(ROOT, "package", "contents", "tools")

a = Analysis(
    ["launcher.py"],
    pathex=[TOOLS],
    binaries=[],
    datas=[],
    hiddenimports=[
        # Reached through the provider registry rather than by a direct
        # import, so the dependency graph alone does not find them.
        "aiusage.normalize",
        "aiusage.providers",
        "psutil",
    ],
    hookspath=[],
    runtime_hooks=[],
    # Nothing here draws anything: the frontend is the Swift app.
    excludes=["tkinter", "unittest", "pydoc", "doctest", "test"],
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="ai-usage-backend",
    debug=False,
    strip=False,
    upx=False,
    console=True,
    target_arch=os.environ.get("AI_USAGE_TARGET_ARCH") or None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    name="backend",
)
