import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


MODULE_PATH = Path(__file__).resolve().parent.parent / "log-relay.py"
SPEC = importlib.util.spec_from_file_location("stage10_log_relay", MODULE_PATH)
log_relay = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(log_relay)


class LogRelayTests(unittest.TestCase):
    def test_classify_response_treats_late_logs_as_dead_letter_but_terminal(self):
        batch = [
            {"file_offset": 0, "raw_message": "a"},
            {"file_offset": 10, "raw_message": "b"},
        ]
        response = {
            "logs": [
                {"file_offset": 0, "disposition": "ACCEPTED"},
                {"file_offset": 10, "disposition": "REJECTED_LATE"},
            ]
        }

        dead = log_relay.classify_response(batch, response)

        self.assertEqual(1, len(dead))
        self.assertEqual("REJECTED_LATE", dead[0]["detail"])

    def test_flush_group_advances_state_even_when_dead_letter_exists(self):
        with tempfile.TemporaryDirectory() as tempdir:
            dead_letter_path = Path(tempdir) / "dead-letter.ndjson"
            state_path = Path(tempdir) / "relay-state.json"
            original_dead_letter = log_relay.DEAD_LETTER_PATH
            original_state_path = log_relay.STATE_PATH
            log_relay.DEAD_LETTER_PATH = dead_letter_path
            log_relay.STATE_PATH = state_path
            try:
                state = {"files": {}}
                group = [
                    {
                        "source": "tomcat-cve-2017-12615",
                        "hostname": "node1",
                        "app_name": "tomcat",
                        "file_path": "/tmp/access.log",
                        "file_offset": 0,
                        "raw_message": "ok",
                        "state_offset": 20,
                    },
                    {
                        "source": "tomcat-cve-2017-12615",
                        "hostname": "node1",
                        "app_name": "tomcat",
                        "file_path": "/tmp/access.log",
                        "file_offset": 10,
                        "raw_message": "late",
                        "state_offset": 40,
                    },
                ]
                response = {
                    "logs": [
                        {"file_offset": 0, "disposition": "ACCEPTED"},
                        {"file_offset": 10, "disposition": "REJECTED_LATE"},
                    ]
                }

                with patch.object(log_relay, "post_records", return_value=response):
                    log_relay.flush_group(group, state, "spool-file")

                self.assertEqual(40, state["files"]["spool-file"])
                self.assertTrue(state_path.exists())
                self.assertTrue(dead_letter_path.exists())
            finally:
                log_relay.DEAD_LETTER_PATH = original_dead_letter
                log_relay.STATE_PATH = original_state_path


if __name__ == "__main__":
    unittest.main()
