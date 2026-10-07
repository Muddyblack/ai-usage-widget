# PyInstaller spec for the Windows tray app. From the repository root:
#
#   pip install -r hosts/windows/build-requirements.txt
#   pyinstaller --noconfirm hosts/windows/ai-usage.spec
#
# Produces dist/AI Usage/AI Usage.exe (one folder: starts faster than a
# one-file build, which unpacks itself on every launch). The QML and the icons
# keep the repository's layout inside the bundle, so hosts/windows/qml/Main.qml finds
# ../../../ui and ../../../package exactly as it does in a checkout.

import glob
import os
import sys

from PyInstaller.utils.hooks import collect_submodules

ROOT = os.path.abspath(os.path.join(SPECPATH, "..", ".."))  # noqa: F821 — set by PyInstaller
TOOLS = os.path.join(ROOT, "package", "contents", "tools")
sys.path.insert(0, TOOLS)


def tree(src, dest):
    return [(src, dest)]


datas = []
datas += tree(os.path.join(ROOT, "hosts", "windows", "qml"), os.path.join("hosts", "windows", "qml"))
datas += tree(os.path.join(ROOT, "package", "contents", "code"), os.path.join("package", "contents", "code"))
datas += tree(os.path.join(ROOT, "package", "contents", "icons"), os.path.join("package", "contents", "icons"))
datas += [(os.path.join(ROOT, "package", "icon.png"), "package")]
# The translation catalogs: app.py picks one, Main.qml parses it with I18n.js.
datas += [(path, "translate") for path in glob.glob(os.path.join(ROOT, "translate", "*.po"))]
# The shared UI (QML and JS); every host reads it from ui/.
for path in glob.glob(os.path.join(ROOT, "ui", "*.qml")) + glob.glob(os.path.join(ROOT, "ui", "*.js")):
    datas.append((path, "ui"))

a = Analysis(  # noqa: F821
    [os.path.join(ROOT, "hosts", "windows", "app.py")],
    pathex=[TOOLS],
    hiddenimports=collect_submodules("aiusage") + ["psutil"],
    datas=datas,
    excludes=["tkinter"],
)
pyz = PYZ(a.pure)  # noqa: F821
exe = EXE(  # noqa: F821
    pyz,
    a.scripts,
    # UTF-8 mode: without it Windows' default text encoding is the ANSI code
    # page (cp1252), for open() and subprocess output alike. The backend names
    # its encodings itself; this covers anything that does not.
    [("X utf8", None, "OPTION")],
    exclude_binaries=True,
    name="AI Usage",
    console=False,
    icon=os.path.join(ROOT, "package", "icon.png"),
)
coll = COLLECT(exe, a.binaries, a.datas, name="AI Usage")  # noqa: F821
