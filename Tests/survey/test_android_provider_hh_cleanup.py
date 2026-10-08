"""Provider-to-H&H cleanup and inventory lease integration regressions."""
from contextlib import contextmanager
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from harness.api import hh_cc_reader_adb_control_plane as control
from harness.api import hh_cc_reader_adb_live as live


class HhCleanupTests(unittest.TestCase):
    def evidence(self):
        catalog = json.loads((ROOT / "Tests/survey/fixtures/hh-cc-reader-adb-control-plane/catalog.json").read_text())
        evidence = copy.deepcopy(next(case["evidence"] for case in catalog["cases"] if case["id"] == "12-network-connect-success"))
        evidence["network_adb"].update({"result": "INCOMPLETE", "cleanup": "FAILED", "usb_revert_issued": False, "readonly_proof_over_network": False, "connect_result": "refused"})
        return evidence

    def test_failed_cleanup_cannot_hide_behind_failed_revert_or_readiness(self):
        for mode in ("tcpip-cert", "classify", "inventory", "probe"):
            for ready in (True, False):
                with self.subTest(mode=mode, ready=ready):
                    evidence = self.evidence()
                    evidence["mode"] = mode
                    if not ready:
                        evidence["adb_devices"] = []
                        evidence["identity"] = {}
                    receipt = control.evaluate_control_plane(evidence)
                    self.assertEqual(receipt["state"], "NETWORK_ADB_REVERT_FAILED")
                    self.assertEqual(receipt["result"], "INCOMPLETE")
                    self.assertEqual(receipt["cleanup"], "FAILED")
                    self.assertIn("cleanup", receipt["next_action"])

    def test_cleanup_failure_cli_is_nonzero(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "input.json"
            source.write_text(json.dumps(self.evidence()))
            self.assertEqual(control.main(["--input", str(source), "--output-dir", temporary]), 2)

    def test_inventory_lease_covers_reads_and_releases_before_certification(self):
        held = False
        reads = []

        @contextmanager
        def lease(directory):
            nonlocal held
            self.assertFalse(held)
            held = True
            try:
                yield
            finally:
                held = False

        def devices(adb, *, lease_held=False):
            self.assertTrue(held)
            self.assertTrue(lease_held)
            return [{"state": "device", "transport": "usb", "_serial": "synthetic", "serial_token": "SERIAL_PRESENT"}]

        def shell(adb, command, serial):
            self.assertTrue(held)
            reads.append(command)
            text = "[ro.serialno]: [synthetic]\n[ro.product.model]: [PAX A80]" if command == "getprop" else "inet 192.0.2.10/24 aa:bb:cc:dd:ee:ff"
            return {"ok": True, "stdout": text}

        def certify(*args, **kwargs):
            self.assertFalse(held)
            self.assertEqual(len(reads), 7)
            return {"result": "INCOMPLETE", "cleanup": "FAILED", "usb_revert_issued": False}

        host = {"chosen": Path("synthetic-adb"), "version": "fixture", "precedence": "owned"}
        with patch.object(live, "resolve_host", return_value=host), patch.object(live, "provider_lease", side_effect=lease), patch.object(live, "collect_usb", return_value={}), patch.object(live, "collect_devices", side_effect=devices), patch.object(live, "allowed_shell", side_effect=shell), patch.object(live, "certify_network", side_effect=certify):
            evidence = live.collect_live_evidence("tcpip-cert", expected_mac="AA-BB-CC-DD-EE-FF", transport_authorized=True)
        self.assertFalse(held)
        self.assertEqual(evidence["network_adb"]["cleanup"], "FAILED")
        self.assertEqual(control.evaluate_control_plane(evidence)["state"], "NETWORK_ADB_REVERT_FAILED")


if __name__ == "__main__":
    unittest.main()
