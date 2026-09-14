#!/usr/bin/env python3
"""Export shared behavioral scenarios through the real backend, offline."""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "package/contents/tools"))

from aiusage.contract import finalize  # noqa: E402
from aiusage.normalize import normalize  # noqa: E402


def scenarios():
    cases = json.loads((ROOT / "tests/behavior/scenarios.json").read_text(encoding="utf-8"))
    for case in cases:
        raw = case.pop("raw", None)
        if raw is not None:
            provider = finalize(normalize(raw))
            case["envelope"] = {"schemaVersion": 1, "active": provider["id"], "providers": [provider]}
    return cases


if __name__ == "__main__":
    print(json.dumps(scenarios()))
