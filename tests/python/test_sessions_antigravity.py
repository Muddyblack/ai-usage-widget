import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from _support import REPO  # noqa: F401
from aiusage import sessions
from aiusage.providers import antigravity_sessions

_CLI_ID = "11111111-1111-4111-8111-111111111111"
_IDE_ID = "22222222-2222-4222-8222-222222222222"


def _write_cli(root: str, session_id: str, content: str, name: str = "transcript.jsonl") -> str:
    path = Path(root) / "antigravity-cli" / "brain" / session_id / ".system_generated" / "logs" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    os.utime(path, (1_767_261_900, 1_767_261_900))
    return str(path)


def _write_ide(root: str, session_id: str, content: str, name: str = "task.md") -> str:
    path = Path(root) / "antigravity" / "brain" / session_id / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return str(path)


class AntigravityDiscoveryTest(unittest.TestCase):
    def test_reads_cli_transcript_and_ide_artifact_without_claiming_foreign_jsonl(self):
        transcript = "\n".join(
            [
                json.dumps(
                    {
                        "step_index": 0,
                        "type": "USER_INPUT",
                        "created_at": "2026-01-01T10:00:00Z",
                        "content": "<USER_REQUEST>Build the widget</USER_REQUEST>",
                    }
                ),
                json.dumps(
                    {
                        "step_index": 1,
                        "type": "PLANNER_RESPONSE",
                        "created_at": "2026-01-01T10:05:00Z",
                        "content": "plan",
                    }
                ),
            ]
        )
        with tempfile.TemporaryDirectory() as root:
            cli_path = _write_cli(root, _CLI_ID, transcript)
            _write_cli(root, "33333333-3333-4333-8333-333333333333", '{"type":"USER_INPUT"}')
            _write_ide(root, _IDE_ID, "# Fix the installer\n\nDetails")
            with mock.patch.dict(os.environ, {"ANTIGRAVITY_HOME": root}, clear=True):
                records = antigravity_sessions.read_recent_sessions()

        self.assertEqual({record.session_id for record in records}, {_CLI_ID, _IDE_ID})
        cli = next(record for record in records if record.session_id == _CLI_ID)
        self.assertEqual(cli.title, "Build the widget")
        self.assertEqual(cli.last_activity, 1_767_261_900)
        self.assertEqual(cli.source_path, cli_path)
        ide = next(record for record in records if record.session_id == _IDE_ID)
        self.assertEqual(ide.title, "Fix the installer")

    def test_deduplicates_cli_and_ide_copies_by_newest_activity(self):
        transcript = json.dumps(
            {
                "step_index": 0,
                "type": "USER_INPUT",
                "created_at": "2026-01-01T10:00:00Z",
                "content": "<USER_REQUEST>CLI title</USER_REQUEST>",
            }
        )
        with tempfile.TemporaryDirectory() as root:
            _write_cli(root, _CLI_ID, transcript)
            ide_path = _write_ide(root, _CLI_ID, "# IDE title")
            os.utime(ide_path, (2_000_000_000, 2_000_000_000))
            with mock.patch.dict(os.environ, {"ANTIGRAVITY_HOME": root}, clear=True):
                records = antigravity_sessions.read_recent_sessions()

        self.assertEqual(len(records), 1)
        self.assertEqual(records[0].title, "IDE title")

    def test_caps_recent_records_and_rejects_invalid_ids(self):
        with tempfile.TemporaryDirectory() as root:
            for index in range(61):
                session_id = f"{index:08d}-0000-4000-8000-000000000000"
                _write_ide(root, session_id, f"# Session {index}")
            _write_ide(root, "not-a-uuid", "# Invalid")
            with mock.patch.dict(os.environ, {"ANTIGRAVITY_HOME": root}, clear=True):
                records = antigravity_sessions.read_recent_sessions()

        self.assertEqual(len(records), 60)
        self.assertNotIn("not-a-uuid", {record.session_id for record in records})


class AntigravitySessionBoundaryTest(unittest.TestCase):
    def test_public_entry_redacts_source_path_and_session_id(self):
        record = antigravity_sessions.AntigravitySession(
            session_id=_CLI_ID,
            title="A useful title",
            last_activity=2_000,
            source_path="/private/.gemini/antigravity-cli/brain/" + _CLI_ID,
        )
        with mock.patch.object(antigravity_sessions, "read_recent_sessions", return_value=[record]):
            entry = sessions._antigravity_entries()[0]

        encoded = json.dumps(entry)
        self.assertEqual(entry["provider"], "antigravity")
        self.assertEqual(entry["sessionName"], "Antigravity")
        self.assertNotIn(record.source_path, encoded)
        self.assertNotIn(_CLI_ID, encoded)
        self.assertRegex(entry["openKey"], r"^[0-9a-f]{64}$")

    def test_target_keeps_real_uuid_for_resume_but_uses_opaque_key(self):
        record = antigravity_sessions.AntigravitySession(
            session_id=_CLI_ID,
            title="Title",
            last_activity=2_000,
            source_path="/private/transcript.jsonl",
        )
        with mock.patch.object(antigravity_sessions, "read_session_targets", return_value=[record]):
            targets = sessions.collect_open_targets()

        key = sessions._open_key("antigravity", _CLI_ID)
        self.assertEqual(targets[key]["id"], _CLI_ID)
        self.assertEqual(targets[key]["keyId"], _CLI_ID)


if __name__ == "__main__":
    unittest.main()
