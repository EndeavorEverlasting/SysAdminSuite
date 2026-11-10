"""Bluetooth incident routing, sealed releases and no-unapproved-OS-mutation regressions."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class BluetoothIncidentRoutingTests(unittest.TestCase):
    def test_incident_has_high_priority_field_route_without_parallel_authority(self):
        manifest = json.loads((ROOT / "harness/api/agent-routing-manifest.json").read_text(encoding="utf-8"))
        hits = [t for t in manifest["triggers"] if t["id"] == "bluetooth-peripheral-incident-trigger"]
        self.assertEqual(len(hits), 1)
        hit = hits[0]
        self.assertEqual(hit["target"], "field-workflow")
        self.assertEqual(hit["composition_mode"], "primary")
        self.assertGreater(hit["priority"], 55)
        self.assertIn("BluetoothUserService", hit["deterministic_task_signals"])

    def test_contract_preserves_root_cause_uncertainty_and_mutation_gates(self):
        policy = json.loads((ROOT / "harness/api/bluetooth-peripheral-incident-route.v1.json").read_text(encoding="utf-8"))
        self.assertEqual(policy["entrypoint"], "Recover-BluetoothPeripheral.cmd")
        self.assertEqual(policy["api_entrypoint"], "SasBluetooth.cmd")
        self.assertIn("DO_NOT_PROVE", policy["causal_rule"])
        self.assertTrue(policy["evidence_policy"]["physical_acceptance_required"])
        self.assertEqual(policy["release"]["promotion"], "SIDE_BY_SIDE_NEW_RELEASE_NO_OVERWRITE_NO_AUTOSWITCH")
        self.assertEqual(policy["ordered_gates"][0]["effect"], "LOCAL_READ_ONLY")
        for gate in policy["ordered_gates"][1:]:
            self.assertTrue(gate["requires_approval"])

    def test_release_command_is_bundled_and_verification_is_closed(self):
        prepare = (ROOT / "scripts/Prepare-BluetoothPeripheralBundle.ps1").read_text(encoding="utf-8")
        runtime = (ROOT / "scripts/SasBluetoothRuntime.psm1").read_text(encoding="utf-8")
        installer = (ROOT / "scripts/Install-BluetoothPeripheralRelease.ps1").read_text(encoding="utf-8")
        cmd = (ROOT / "Install-BluetoothPeripheralRelease.cmd").read_text(encoding="utf-8")
        for entry in ("Install-BluetoothPeripheralRelease.cmd", "scripts/Install-BluetoothPeripheralRelease.ps1"):
            self.assertIn(entry, prepare)
            self.assertIn(entry, runtime)
        self.assertIn("BUNDLE_UNLISTED_FILE", runtime)
        self.assertIn("BUNDLE_DUPLICATE_ENTRY", runtime)
        self.assertIn("BUNDLE_REPARSE_POINT", runtime)
        self.assertIn("SOURCE_COMMIT_NOT_APPROVED", installer)
        self.assertIn("RELEASE_ALREADY_EXISTS", installer)
        self.assertIn("Test-SasBluetoothBundle $stage", installer)
        self.assertIn("AutoActivated=$false", installer)
        self.assertIn("%~dp0scripts\\Install-BluetoothPeripheralRelease.ps1", cmd)

    def test_repair_avoids_service_policy_and_peripheral_preference_mutation(self):
        source = (ROOT / "scripts/Invoke-BluetoothPeripheralRecovery.ps1").read_text(encoding="utf-8")
        self.assertIn("Start-Service", source)
        for unsafe in ("Set-Service", "Remove-PnpDevice", "Set-ItemProperty", "Remove-ItemProperty", "StartType Automatic"):
            self.assertNotIn(unsafe, source)


@unittest.skipUnless(os.name == "nt" and (Path(os.environ.get("ProgramFiles(x86)", "missing")) /
                                          "Windows Kits/10/UnionMetadata").exists(),
                     "Windows SDK preparation host needed")
class BluetoothReleaseWindowsTests(unittest.TestCase):
    def test_prepare_install_side_by_side_and_deny_extra_file(self):
        with tempfile.TemporaryDirectory(prefix="SAS release fixture ") as folder:
            root = Path(folder)
            bundle = root / "approved bundle"
            prep = subprocess.run(["cmd.exe", "/d", "/c", "call", str(ROOT / "SasBluetooth.cmd"),
                                   "prepare", "-Destination", str(bundle)],
                                  capture_output=True, text=True, timeout=90)
            self.assertEqual(prep.returncode, 0, prep.stdout + prep.stderr)
            manifest = json.loads((bundle / "bluetooth-bundle.json").read_text(encoding="utf-8-sig"))
            approved = manifest["SourceCommit"]
            self.assertRegex(approved, r"^[0-9a-f]{40}$")
            releases = root / "releases"
            def install():
                return subprocess.run(["cmd.exe", "/d", "/c", "call",
                    str(bundle / "Install-BluetoothPeripheralRelease.cmd"),
                    "-ApprovedCommit", approved, "-ReleaseRoot", str(releases)],
                    capture_output=True, text=True, timeout=35)
            first = install()
            self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
            target = releases / ("release-" + approved)
            self.assertTrue((target / "SasBluetooth.cmd").is_file())
            self.assertNotEqual(install().returncode, 0, "No overwrite of prior approved release")
            (bundle / "unlisted.cmd").write_text("@echo off\n", encoding="utf-8")
            self.assertNotEqual(install().returncode, 0, "Extra executable must invalidate seal")


if __name__ == "__main__":
    unittest.main()
