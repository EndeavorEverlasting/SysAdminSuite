"""Producer/consumer semantic compatibility fixtures independent of host tasks."""
from copy import deepcopy
import json
from pathlib import Path
from subprocess import run
import sys
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "sas_antivirus_semantics.py"
sys.path.insert(0, str(SCRIPT.parent))
import sas_antivirus_semantics as semantics


class AntivirusSemanticsTest(unittest.TestCase):
    def setUp(self):
        self.contract = {
            "schema_version": "filesteward.antivirus-detection/v1",
            "owner": "FileSteward",
            "scheduler": {
                "consumer": "SysAdminSuite",
                "operations": {"check": "VALIDATE_POLICY_AND_SCOPE", "run": "INSPECT_APPROVED_SCOPE"},
                "transport": "EXIT_STATUS_ONLY",
                "exit_codes": {
                    "COMPLETED": 0, "LOCAL_STATE_UNAVAILABLE": 1, "INCOMPLETE": 10,
                    "POLICY_REJECTED": 12, "DEPENDENCY_UNAVAILABLE": 13,
                },
                "completion_is_match_independent": True,
                "forwards_file_evidence": False,
                "grants_action_authority": False,
            },
        }

    def test_exact_exit_projection(self):
        self.assertTrue(semantics.validate_filesteward_contract(self.contract))
        self.assertEqual(semantics.FILESTEWARD_RESULTS, {
            0: "SCAN_COMPLETED", 1: "SCAN_FAILED", 10: "SCAN_INCOMPLETE",
            12: "DETECTOR_POLICY_REJECTED", 13: "DETECTOR_DEPENDENCY_UNAVAILABLE",
        })

    def test_refuses_ambiguous_or_evidence_bearing_contracts(self):
        for key, value in (
            ("transport", "JSON_FINDINGS"),
            ("forwards_file_evidence", True),
            ("grants_action_authority", True),
            ("completion_is_match_independent", False),
            ("paths", ["/private/path"]),
        ):
            with self.subTest(key=key):
                modified = deepcopy(self.contract)
                modified["scheduler"][key] = value
                self.assertFalse(semantics.validate_filesteward_contract(modified))
        self.contract["scheduler"]["exit_codes"]["COMPLETED"] = False
        self.assertFalse(semantics.validate_filesteward_contract(self.contract))

    def test_cli_rejects_duplicate_keys_and_never_echoes_input(self):
        command = [sys.executable, "-I", str(SCRIPT), "-"]
        compatible = run(command, input=json.dumps(self.contract), capture_output=True, text=True)
        self.assertEqual(compatible.returncode, 0)
        altered = '{"owner":"private", ' + json.dumps(self.contract)[1:]
        rejected = run(command, input=altered, capture_output=True, text=True)
        self.assertEqual(rejected.returncode, 1)
        self.assertEqual(rejected.stdout.strip(), "FILESTEWARD_SCHEDULER_CONTRACT_REJECTED")
        self.assertEqual(rejected.stderr, "")


if __name__ == "__main__":
    unittest.main()
