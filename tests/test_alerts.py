import datetime as dt
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts import agent_alertd


class StoreTests(unittest.TestCase):
    def test_store_round_trips_alerts_atomically(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "alerts.json"
            store = agent_alertd.Store(path)
            alert = {"id": "abc", "status": "pending", "title": "test"}
            store.add(alert)
            self.assertEqual(store.list(), [alert])
            self.assertEqual(store.update("abc", status="fired")["status"], "fired")
            self.assertEqual(json.loads(path.read_text())["alerts"][0]["status"], "fired")

    def test_time_parsing_normalizes_to_utc(self):
        value = agent_alertd.parse_when("2026-11-14T09:00:00-05:00")
        self.assertEqual(value, dt.datetime(2026, 11, 14, 14, 0, tzinfo=dt.timezone.utc))

    def test_relative_duration_is_agent_friendly(self):
        with mock.patch.object(agent_alertd, "now", return_value=dt.datetime(2026, 11, 13, tzinfo=dt.timezone.utc)):
            self.assertEqual(
                agent_alertd.parse_after("1h30m"),
                dt.datetime(2026, 11, 13, 1, 30, tzinfo=dt.timezone.utc),
            )

    def test_command_template_is_tokenized_without_shell(self):
        alert = {"id": "abc", "title": "A title", "message": "hello", "agent": "codex", "resume_command": "codex resume --label '{title}'"}
        self.assertEqual(agent_alertd.command_for(alert, "resume"), ["codex", "resume", "--label", "A title"])

    def test_notify_is_non_blocking(self):
        with mock.patch.object(agent_alertd.subprocess, "Popen") as popen:
            agent_alertd.notify({"title": "hello", "message": "world"})
            popen.assert_called_once()


if __name__ == "__main__":
    unittest.main()
