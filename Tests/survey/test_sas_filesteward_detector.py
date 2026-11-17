"""Tests for the status-only FileSteward job and independent scheduler ownership."""
import json
import sys
import tempfile
import unittest
from pathlib import Path
from subprocess import CompletedProcess
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import sas_antivirus as av


class DetectorScheduleTest(unittest.TestCase):
    def test_status_boundary_and_private_receipts(self):
        for code, expected in av.FILESTEWARD_RESULTS.items():
            with self.subTest(code=code), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                scanner = av.filesteward_scanner(Path(sys.executable), "f" * 64)
                response = CompletedProcess(scanner.command, code, "private path/digest", "private error")
                with patch.object(av, "execute", return_value=response) as execute, \
                        patch.object(av, "platform_name", return_value="linux"), \
                        patch.object(av, "discover") as discover, patch.object(av, "sync_candidates") as sync:
                    receipt, _ = av.run_once(directory, scanner)
                discover.assert_not_called()
                sync.assert_not_called()
                execute.assert_called_once_with(scanner.command, timeout=90, cwd=None)
                self.assertEqual(receipt["provider"], "filesteward")
                self.assertEqual(receipt["status"], expected)
                stored = json.loads((directory / "latest.json").read_text())
                self.assertEqual(stored, receipt)
                self.assertNotIn("private", json.dumps(stored))
                self.assertNotIn("f" * 64, json.dumps(stored))

    def test_detector_cron_remove_keeps_provider_and_unrelated_entries(self):
        existing = b"# user job\r\n0 1 * * 1 provider" + av.CRON_MARKER.encode() + b"\r\n"
        detector_line = av.cron_line(("/safe/scheduler", "run"), "Friday", "07:25", detector=True)
        existing += detector_line.encode() + b"\n"
        with patch.object(av.shutil, "which", return_value="/usr/bin/crontab"), \
                patch.object(av.subprocess, "run", side_effect=[
                    CompletedProcess([], 0, existing, b""), CompletedProcess([], 0)
                ]) as run:
            self.assertEqual(av.apply_cron(None, detector=True), "REMOVED")
        self.assertEqual(run.call_args.kwargs["input"], existing[:existing.index(detector_line.encode())])

    def test_windows_detector_uses_independent_task(self):
        with patch.object(av, "powershell", side_effect=lambda source: (source,)), \
                patch.object(av, "execute", return_value=CompletedProcess([], 0, "REMOVED\n")) as execute:
            self.assertEqual(av.apply_windows_task(None, detector=True), "REMOVED")
        self.assertIn("SysAdminSuite-FileStewardDetector-", execute.call_args.args[0][0])
        self.assertIn("SysAdminSuite FileSteward Detector", execute.call_args.args[0][0])

    def test_detector_receipts_cannot_be_projected_manually(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            for status in ("SCAN_INCOMPLETE", *av.DETECTOR_ACTIONS):
                av.persist(directory, av.new_receipt("linux", "filesteward", status))
            self.assertEqual(av.sync_candidates(directory), "NO_ACTIONABLE_GAPS")
            for status in av.DETECTOR_ACTIONS:
                self.assertIsNone(av.development_candidate(status))

    def test_receipt_schema_rejects_detector_findings_and_sync(self):
        try:
            from jsonschema import Draft202012Validator
        except ImportError:
            self.skipTest("jsonschema unavailable")
        schema = json.loads((ROOT / "schemas/harness/host-antivirus-receipt.schema.json").read_text())
        validator = Draft202012Validator(schema)
        receipt = av.new_receipt("linux", "filesteward", "SCAN_COMPLETED")
        self.assertTrue(validator.is_valid(receipt))
        self.assertFalse(validator.is_valid(dict(receipt, status="DETECTION_REPORTED")))
        self.assertFalse(validator.is_valid(dict(receipt, repository_sync="SYNCED_LOCAL")))
        self.assertFalse(validator.is_valid(dict(receipt, path="/private")))

    def test_missing_interpreter_becomes_a_failed_scan_receipt(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            scanner = av.filesteward_scanner(directory / "missing", "a" * 64)
            with patch.object(av, "platform_name", return_value="linux"):
                receipt, code = av.run_once(directory, scanner)
            self.assertEqual(code, 1)
            self.assertEqual(receipt["status"], "SCAN_FAILED")


if __name__ == "__main__":
    unittest.main()
