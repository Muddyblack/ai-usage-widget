"""MiMo Code local usage. Its SQLite schema matches OpenCode's v1 ledger."""

import os
from dataclasses import replace
from pathlib import Path

from .. import paths
from . import opencode


def discover_database_paths():
    explicit = os.environ.get("MIMO_DB", "").strip()
    if explicit:
        candidate = Path(explicit).expanduser()
        if candidate.is_file():
            return [str(candidate)]
        if candidate.is_absolute():
            return []
        for base in paths.data_home_dirs():
            for directory in (Path(base), Path(base) / "mimocode"):
                path = directory / candidate
                if path.is_file():
                    return [str(path)]
        return []
    return list(
        dict.fromkeys(
            str(path)
            for base in paths.data_home_dirs()
            for path in sorted((Path(base) / "mimocode").glob("mimocode*.db"))
            if path.is_file()
        )
    )


def read_recent_sessions(*, include_all=False):
    records = []
    for database in discover_database_paths():
        for record in opencode._read_database(database, include_all=include_all, import_tables=("external_import", "claude_import")):
            records.append(replace(record, usage=tuple(bucket._replace(source="mimo") for bucket in record.usage)))
    return records


def read_session_targets(*, include_all=True):
    return read_recent_sessions(include_all=include_all)


def usage_snapshot():
    return opencode.usage_snapshot(records=read_recent_sessions(include_all=True))
