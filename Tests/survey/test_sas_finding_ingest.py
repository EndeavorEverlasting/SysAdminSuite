#!/usr/bin/env python3
"""Offline behavioral tests: private event intake, dedup, and safe publication candidates."""
from __future__ import annotations

import copy
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "harness" / "api" / "sas_finding_ingest.py"
spec = importlib.util.spec_from_file_location("sas_finding_ingest", MODULE)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def sample():
    return {
        "schema_version": "sas-finding-event/v1",
        "event_id": "test-event-00000001",
        "logical_subject_key": "PRIVATE-HOST-DONT-PUBLISH",
        "event_type": "FINDING_RECORDED",
        "occurred_at": "2026-10-09T21:04:00-04:00",
        "evidence_ref": "https://private.invalid/secret-drive-folder",
        "category": "hardware",
        "proof_level": "operator_reported",
        "privacy": "private_operational",
        "finding": {"summary": "Secret hostname, monitor, purchased part", "details": "123-PRIVATE-DEVICE-SERIAL", "measurements": {"serial": "EXAMPLE-SECRET"}},
    }


class FindingIngestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_record_private_and_only_constant_public_fields(self):
        event = sample()
        result = mod.ingest(event, self.root)
        self.assertEqual(result["admission_state"], "RECORDED_PRIVATE")
        self.assertFalse(result["external_push_performed"])
        saved = json.loads((self.root / "private" / (event["event_id"] + ".json")).read_text())
        self.assertEqual(saved, event)
        public = (self.root / "candidates" / (event["event_id"] + ".json")).read_text()
        for secret in ("PRIVATE-HOST", "secret-drive", "DEVICE-SERIAL", "EXAMPLE-SECRET", "Secret hostname", event["event_id"], "2026-10-09"):
            self.assertNotIn(secret, public)
        self.assertEqual(json.loads(public)["approval_state"], "REVIEW_REQUIRED")
        self.assertFalse((self.root / ".git").exists())

    def test_identical_event_is_idempotent(self):
        event = sample()
        mod.ingest(event, self.root)
        result = mod.ingest(event, self.root)
        self.assertEqual(result["admission_state"], "IDEMPOTENT_REPLAY")
        self.assertEqual(len(list((self.root / "private").glob("*.json"))), 1)

    def test_conflicting_event_fails_without_modifying_evidence(self):
        event = sample()
        mod.ingest(event, self.root)
        before = (self.root / "private" / "test-event-00000001.json").read_bytes()
        event["finding"]["summary"] = "different"
        with self.assertRaisesRegex(mod.AdmissionError, "CONFLICT"):
            mod.ingest(event, self.root)
        self.assertEqual(before, (self.root / "private" / "test-event-00000001.json").read_bytes())

    def test_invalid_fields_and_status_fail_closed(self):
        event = sample()
        for key, value in (("category", "raw screenshot"), ("privacy", "PUBLIC"), ("proof_level", "production_proven"), ("occurred_at", "2026-10-09")):
            bad = copy.deepcopy(event)
            bad[key] = value
            with self.subTest(key=key), self.assertRaises(mod.AdmissionError):
                mod.ingest(bad, self.root)
        bad = sample()
        bad["drive_credentials"] = "secret"
        with self.assertRaises(mod.AdmissionError):
            mod.ingest(bad, self.root)
        self.assertFalse((self.root / "private").exists())

    def test_path_traversal_event_id_rejected(self):
        event = sample()
        event["event_id"] = "../../.github"
        with self.assertRaises(mod.AdmissionError):
            mod.ingest(event, self.root)

    def test_full_repository_root_rejected_as_output(self):
        with self.assertRaises(mod.AdmissionError):
            mod._root(str(ROOT / "docs"))

    def test_stdin_cli_receipt_and_no_private_stdout(self):
        event = sample()
        run = subprocess.run([sys.executable, str(MODULE), "--input", "-", "--output-root", str(self.root)], input=json.dumps(event), capture_output=True, text=True, check=False)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertNotIn("PRIVATE-HOST", run.stdout)
        self.assertEqual(json.loads(run.stdout)["private_evidence_state"], "PERSISTED_LOCAL")

    def test_cli_rejects_malformed_without_leaking(self):
        run = subprocess.run([sys.executable, str(MODULE), "--input", "-", "--output-root", str(self.root)], input="PRIVATE SECRET invalid JSON", capture_output=True, text=True, check=False)
        self.assertEqual(run.returncode, 2)
        self.assertNotIn("SECRET", run.stdout + run.stderr)

    def test_schema_validates_synthetic_event(self):
        schema = json.loads((ROOT / "schemas" / "harness" / "sas-finding-event.schema.json").read_text())
        self.assertEqual(set(schema["required"]), mod.REQUIRED)
        self.assertFalse(schema["additionalProperties"])
        self.assertEqual(set(schema["properties"]["category"]["enum"]), mod.CATEGORIES)
        self.assertEqual(set(schema["properties"]["proof_level"]["enum"]), mod.PROOF)


if __name__ == "__main__":
    unittest.main()
