"""Save a picture of the popup as a PNG or SVG file, for every frontend.

The UI grabs the popup to a temporary PNG (ui/AppState.qml, exportSnapshot) and
hands it here to finish: a PNG is moved to its destination (flattened onto the
popup's dark background when Pillow or ImageMagick is there to do it), an SVG is
a wrapper that embeds the PNG, so the picture scales on a page without a second
renderer. backend/sh/export-snapshot runs this for the process-based hosts; the
desktop tray app calls :func:`export` in-process.

  python -m aiusage.snapshot_export png <src.png> <dest> [width height]
  python -m aiusage.snapshot_export svg <src.png> <dest> [width height]

Prints one JSON object — {"ok":true,"path":…} or {"error":…} — and exits 0 once
it has, so the shell tool falls back only when Python itself could not run.
"""

import base64
import json
import os
import shutil
import subprocess
import sys

BACKGROUND = (13, 13, 26)
BACKGROUND_HEX = "#{:02x}{:02x}{:02x}".format(*BACKGROUND)


def _png(src, dest):
    """Move src to dest, flattening any transparency onto the dark background
    the popup is drawn over, when a tool for that is available."""
    for tool in ("magick", "convert"):
        if shutil.which(tool):
            result = subprocess.run([tool, src, "-background", BACKGROUND_HEX, "-flatten", dest], capture_output=True)
            if result.returncode == 0:
                return
    try:
        from PIL import Image

        img = Image.open(src).convert("RGBA")
        flat = Image.new("RGBA", img.size, BACKGROUND + (255,))
        flat.paste(img, mask=img.split()[3])
        flat.convert("RGB").save(dest, "PNG")
        return
    except ImportError:
        pass
    shutil.copyfile(src, dest)


def _svg(src, dest, width, height):
    with open(src, "rb") as fh:
        data = base64.b64encode(fh.read()).decode()
    background = BACKGROUND_HEX
    svg = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
        f'width="{width}" height="{height}" viewBox="0 0 {width} {height}">\n'
        f'  <rect width="{width}" height="{height}" fill="{background}" rx="10"/>\n'
        f'  <image width="{width}" height="{height}" href="data:image/png;base64,{data}"/>\n'
        "</svg>\n"
    )
    with open(dest, "w", encoding="utf-8") as fh:
        fh.write(svg)


def export(fmt, src, dest, width=800, height=600):
    """Finish an export; returns {"ok": True, "path": dest} or {"error": …}."""
    dest = os.path.expanduser(dest)
    if fmt not in ("png", "svg"):
        return {"error": f"unknown format: {fmt}"}
    if not src or not dest:
        return {"error": "usage: snapshot_export <png|svg> <src.png> <dest> [width height]"}
    if not os.path.isfile(src):
        return {"error": f"source file not found: {src}"}
    try:
        os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
        if fmt == "png":
            _png(src, dest)
        else:
            _svg(src, dest, int(width), int(height))
    except (OSError, ValueError) as exc:
        return {"error": str(exc)}
    finally:
        # The temporary grab is ours to clean up; never remove the destination.
        if os.path.abspath(src) != os.path.abspath(dest):
            try:
                os.remove(src)
            except OSError:
                pass
    return {"ok": True, "path": dest}


def main(argv):
    args = list(argv[1:]) + [""] * 5
    result = export(args[0], args[1], args[2], args[3] or 800, args[4] or 600)
    sys.stdout.write(json.dumps(result, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
