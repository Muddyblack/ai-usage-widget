"""CodeRabbit review usage from its own CLI.

``coderabbit usage`` prints a short plain-text report for the signed-in
account. The widget runs it as is — it makes the CLI's own request, so no key is
handled here — and only keeps the labelled lines it understands.
"""

import re
import shutil
import subprocess

from .. import paths
from ..contract import epoch_of

_LINE = re.compile(r"^\s*([A-Za-z][A-Za-z ]*?)\s*:\s*(.+?)\s*$")
_TIMEOUT = 20


def _binary():
    return shutil.which("coderabbit") or ""


def parse_report(text):
    """The labelled fields of a ``coderabbit usage`` report, or None when the
    text is not one."""
    if "usage" not in (text or "").split("\n", 1)[0].lower():
        return None
    fields = {}
    for line in text.splitlines()[1:]:
        match = _LINE.match(line)
        if match:
            fields[match.group(1).strip().lower()] = match.group(2)
    reviews = re.search(r"\d+", fields.get("your reviews", ""))
    return {
        "organization": fields.get("organization", ""),
        "plan": fields.get("plan", ""),
        "user": fields.get("user", ""),
        "billing": fields.get("usage billing", ""),
        "reviews": int(reviews.group()) if reviews else None,
        "resetAt": epoch_of(fields.get("period resets", "").strip() + "T00:00:00Z")
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", fields.get("period resets", "").strip())
        else 0,
    }


def get_coderabbit_usage():
    binary = _binary()
    if not binary:
        return {}
    try:
        done = subprocess.run(
            [binary, "usage"],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=_TIMEOUT,
            **paths.no_window(),
        )
    except subprocess.TimeoutExpired:
        return {"error": "timed out"}
    except (OSError, subprocess.SubprocessError):
        return {}
    report = parse_report(done.stdout) if done.returncode == 0 else None
    if report is None:
        return {"error": "not signed in — run coderabbit auth login"}
    return report
