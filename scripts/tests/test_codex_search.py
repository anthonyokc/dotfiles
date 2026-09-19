import contextlib
import io
import json
from pathlib import Path
import runpy
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile


SCRIPT = Path(__file__).resolve().parents[1] / "codex-search"
SEARCH = runpy.run_path(str(SCRIPT))


class CodexSearchTests(unittest.TestCase):
    def test_windows_path(self):
        self.assertEqual(SEARCH["wsl_path"](r"C:\Users\AnthonyFlores\.codex"),
                         "/mnt/c/Users/AnthonyFlores/.codex")

    def test_search_filters_and_read_only_database(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            transcript = home / "rollout.jsonl"
            records = [
                {"type": "response_item", "payload": {
                    "type": "message", "role": role,
                    "content": [{"type": "output_text", "text": text}]}}
                for role, text in [("developer", "integration tests"),
                                   ("user", "orange bicycle"),
                                   ("assistant", "Write integration tests before release.")]
            ]
            transcript.write_text("\n".join(json.dumps(r) for r in records) + "\ninvalid\n")
            database = home / "state_5.sqlite"
            with sqlite3.connect(database) as db:
                db.execute("CREATE TABLE threads (id, title, first_user_message, cwd, updated_at, rollout_path)")
                db.executemany("INSERT INTO threads VALUES (?, ?, ?, ?, ?, ?)", [
                    ("match", "Release", "orange bicycle", "/project/sub", 1788825600, str(transcript)),
                    ("outside", "Release", "orange bicycle", "/project-other", 1788825600, str(transcript)),
                ])
            before = database.read_bytes()

            def invoke(*arguments):
                output = io.StringIO()
                errors = io.StringIO()
                with patch.object(sys, "argv", [str(SCRIPT), "integration tests", "--codex-home",
                                               directory, "--index", str(home / "search.sqlite3"),
                                               "--json", *arguments]):
                    with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                        SEARCH["main"]()
                return json.loads(output.getvalue()), errors.getvalue()

            results, errors = invoke("--cwd", "/project")
            self.assertEqual([r["id"] for r in results], ["match"])
            self.assertEqual(results[0]["role"], "assistant")
            self.assertEqual(results[0]["line"], 3)
            self.assertIn("integration tests", results[0]["excerpt"])
            self.assertIn("malformed lines", errors)
            self.assertEqual(invoke("--user-only", "--min-score", "90")[0], [])
            self.assertEqual(invoke("--since", "2099-01-01")[0], [])
            self.assertEqual(len(invoke("--limit", "1")[0]), 1)
            transcript.unlink()
            self.assertIn("unreadable transcripts", invoke()[1])
            self.assertEqual(database.read_bytes(), before)

    def test_missing_codex_database_does_not_block_chatgpt_search(self):
        with tempfile.TemporaryDirectory() as directory:
            index = Path(directory) / "search.sqlite3"
            with contextlib.redirect_stdout(io.StringIO()):
                results = SEARCH["search_main"]([
                    "tests", "--codex-home", directory, "--index", str(index), "--json"
                ])
            self.assertEqual(results, [])
            self.assertFalse((Path(directory) / "state_5.sqlite").exists())
            self.assertTrue(index.exists())

    def test_imports_official_shards_and_incremental_universal_updates(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            index = root / "search.sqlite3"
            official = root / "official.zip"
            conversation = {
                "id": "chat-1",
                "title": "NordicTrack repair",
                "create_time": 100,
                "update_time": 200,
                "mapping": {
                    "u": {"message": {"id": "u", "create_time": 101,
                        "author": {"role": "user"},
                        "content": {"parts": ["The treadmill belt slips."]}}},
                    "a": {"message": {"id": "a", "create_time": 102,
                        "author": {"role": "assistant"},
                        "content": {"parts": ["Check the rear roller bolts."]}}},
                },
            }
            with zipfile.ZipFile(official, "w") as archive:
                archive.writestr("conversations-000.json", json.dumps([conversation]))

            with SEARCH["open_index"](index) as db:
                first = SEARCH["import_chatgpt_archive"](db, official)
                results = SEARCH["search_index"](db, "roller bolts")
            self.assertEqual(first["indexed"], 1)
            self.assertEqual(results[0]["source"], "chatgpt")
            self.assertEqual(results[0]["id"], "chat-1")

            incremental = root / "incremental.zip"
            payload = {"conversations": [{
                "id": "chat-1", "title": "NordicTrack repair", "updated_at": 300,
                "messages": [
                    {"id": "u2", "role": "user", "content": "The motor now squeals."},
                    {"id": "a2", "role": "assistant", "content": "Inspect the drive motor bearing."},
                ],
            }]}
            with zipfile.ZipFile(incremental, "w") as archive:
                archive.writestr("universal/conversations.json", json.dumps(payload))

            with SEARCH["open_index"](index) as db:
                second = SEARCH["import_chatgpt_archive"](db, incremental)
                old = SEARCH["search_index"](db, "roller bolts")
                new = SEARCH["search_index"](db, "motor bearing")
                count = db.execute(
                    "SELECT count(*) FROM messages_fts WHERE source='chatgpt' AND conversation_id='chat-1'"
                ).fetchone()[0]
            self.assertEqual(second["indexed"], 1)
            self.assertEqual(old, [])
            self.assertEqual(new[0]["id"], "chat-1")
            self.assertEqual(count, 2)


if __name__ == "__main__":
    unittest.main()
