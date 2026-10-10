"""JetBrains AI Assistant credits, read from the IDE's own options file.

The IDE keeps its AI quota in
``<config>/<vendor>/<IDE><version>/options/AIAssistantQuotaManager2.xml`` as two
JSON documents stored in XML attributes (``quotaInfo`` and ``nextRefill``). It
is refreshed by the IDE whenever it talks to JetBrains, so this provider opens
no socket and reads no credential: the figures are as fresh as the last time an
IDE was running.

Of every IDE installed, the one whose file was written last wins, because that
is the one the user is working in.
"""

import glob
import json
import os
import re
import xml.etree.ElementTree as ET

from .. import paths
from ..contract import epoch_of, finite_number

_FILE = "AIAssistantQuotaManager2.xml"
_MAX_BYTES = 2 * 1024 * 1024
_VENDORS = ("JetBrains", "Google")  # Android Studio is under Google.
_IDE_NAMES = {
    "IntelliJIdea": "IntelliJ IDEA",
    "IdeaIC": "IntelliJ IDEA Community",
    "PyCharm": "PyCharm",
    "PyCharmCE": "PyCharm Community",
    "WebStorm": "WebStorm",
    "PhpStorm": "PhpStorm",
    "GoLand": "GoLand",
    "CLion": "CLion",
    "Rider": "Rider",
    "RustRover": "RustRover",
    "RubyMine": "RubyMine",
    "DataGrip": "DataGrip",
    "DataSpell": "DataSpell",
    "AndroidStudio": "Android Studio",
    "Aqua": "Aqua",
    "Writerside": "Writerside",
}
_VERSION_RE = re.compile(r"^(.*?)(\d{4}\.\d+(?:\.\d+)?)$")


def _candidates():
    explicit = os.environ.get("JETBRAINS_QUOTA_FILE")
    if explicit:
        return [explicit]
    found = []
    for base in paths.electron_app_data_dirs():
        for vendor in _VENDORS:
            found.extend(glob.glob(os.path.join(glob.escape(os.path.join(base, vendor)), "*", "options", _FILE)))
    return found


def _mtime(path):
    try:
        return os.path.getmtime(path)
    except OSError:
        return 0


def ide_name(path):
    """ "IntelliJIdea2025.3" -> "IntelliJ IDEA 2025.3" from the folder name."""
    folder = os.path.basename(os.path.dirname(os.path.dirname(path)))
    match = _VERSION_RE.match(folder)
    if not match:
        return folder
    name = _IDE_NAMES.get(match.group(1), match.group(1))
    return f"{name} {match.group(2)}".strip()


def _json_attribute(root, name):
    """The JSON stored under `name`, either as a plain attribute or as the
    value of an ``<option name="...">`` element, which is how IntelliJ's
    persistent state writes it."""
    for element in root.iter():
        raw = element.get(name)
        if raw is None and element.get("name") == name:
            raw = element.get("value")
        if not isinstance(raw, str) or not raw.strip():
            continue
        try:
            value = json.loads(raw)
        except ValueError:
            continue
        if isinstance(value, dict):
            return value
    return None


def _amount(block, key):
    return finite_number((block or {}).get(key), minimum=0) if isinstance(block, dict) else None


def read_quota(path):
    """The parsed quota of one options file, or {"error": ...}."""
    try:
        if os.path.getsize(path) > _MAX_BYTES:
            return {"error": "options file too large"}
        root = ET.parse(path).getroot()
    except (OSError, ET.ParseError):
        return {"error": "unreadable options file"}
    quota = _json_attribute(root, "quotaInfo")
    if quota is None:
        return {"error": "no AI quota recorded yet"}
    refill = _json_attribute(root, "nextRefill") or {}
    tariff = quota.get("tariffQuota") if isinstance(quota.get("tariffQuota"), dict) else quota
    top_up = quota.get("topUpQuota") if isinstance(quota.get("topUpQuota"), dict) else {}
    used = _amount(tariff, "current")
    maximum = _amount(tariff, "maximum")
    available = _amount(tariff, "available")
    if used is None and maximum is not None and available is not None:
        used = max(0.0, maximum - available)
    if available is None and maximum is not None and used is not None:
        available = max(0.0, maximum - used)
    if used is None or maximum is None:
        return {"error": "no AI quota recorded yet"}
    return {
        "ide": ide_name(path),
        "state": quota.get("type") if isinstance(quota.get("type"), str) else "",
        "used": used,
        "maximum": maximum,
        "available": available if available is not None else 0.0,
        "topUpAvailable": _amount(top_up, "available") or 0.0,
        "topUpMaximum": _amount(top_up, "maximum") or 0.0,
        # The refill date, not `until`: that one is the subscription's end.
        "resetAt": epoch_of(refill.get("next")),
        "recordedAt": _mtime(path),
    }


def get_jetbrains_usage():
    files = sorted(_candidates(), key=_mtime, reverse=True)
    if not files or not os.path.isfile(files[0]):
        return {}
    return read_quota(files[0])
