"""Behavioral negative controls for the reusable offline AndroidProvider."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from harness.api import android_provider as provider


class ProviderTests(unittest.TestCase):
    def archive(self, root, extra=None):
        archive = root / "official.fixture.zip"
        with zipfile.ZipFile(archive, "w") as zipped:
            for name in provider.REQUIRED_COMPONENTS:
                zipped.writestr("platform-tools/" + name, "Pkg.Revision=36.0.0\n" if name == "source.properties" else "synthetic-binary")
            if extra:
                zipped.writestr(*extra)
        return archive

    def test_offline_qualification_and_roles(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = self.archive(root)
            destination = root / "owned"
            with patch("urllib.request.urlopen", side_effect=AssertionError("network forbidden")):
                manifest = provider.prepare_bundle(archive, provider.sha256(archive), destination)
            self.assertEqual(provider.verify_bundle(destination)["state"], "READY")
            self.assertEqual(manifest["version"], "36.0.0")
            with patch.object(provider, "_run", return_value=subprocess.CompletedProcess([], 0, "ADB version fixture", "")), patch.object(provider, "_which", return_value=root / "competing/adb.exe"):
                for role in provider.ROLES:
                    status = provider.AndroidProvider(role, destination).status()
                    self.assertTrue(status["offline_ready"])
                    self.assertEqual(status["competing_runtime_count"], 1)
                    self.assertEqual(status["runtime"], "SAS_OWNED_PLATFORM_TOOLS")

    def test_missing_hash_corrupt_extra_components(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = self.archive(root)
            directory = root / "owned"
            self.assertEqual(provider.verify_bundle(directory)["state"], "MISSING_BUNDLE")
            with self.assertRaisesRegex(RuntimeError, "ARCHIVE_HASH_MISMATCH"):
                provider.prepare_bundle(archive, "0" * 64, directory)
            provider.prepare_bundle(archive, provider.sha256(archive), directory)
            binary = directory / "adb.exe"
            original = binary.read_bytes()
            binary.write_bytes(b"truncated")
            self.assertEqual(provider.verify_bundle(directory)["state"], "HASH_MISMATCH")
            with patch.object(provider, "_run", side_effect=AssertionError("unqualified binary executed")):
                self.assertIsNone(provider.resolve_host(directory)["chosen"])
            binary.write_bytes(original)
            binary.unlink()
            self.assertEqual(provider.verify_bundle(directory)["state"], "INCOMPLETE_BUNDLE")
            binary.write_bytes(original)
            (directory / "extra.exe").write_bytes(b"unmanifested")
            self.assertEqual(provider.verify_bundle(directory)["state"], "UNMANIFESTED_COMPONENT")

    def test_archive_traversal_and_keys_rejected(self):
        for extra in (("platform-tools/../escape", "x"), ("platform-tools//escape.txt", "x"), ("platform-tools/adbkey", "secret"), ("platform-tools/ADB.EXE", "duplicate")):
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                archive = self.archive(root, extra)
                with self.assertRaisesRegex(RuntimeError, "UNSAFE_ARCHIVE_ENTRY"):
                    provider.prepare_bundle(archive, provider.sha256(archive), root / "owned")
                self.assertFalse((root / "escape").exists())

    def test_classification_and_unknown(self):
        self.assertEqual(provider.classify_devices([]), "NO_ANDROID_DEVICE")
        self.assertEqual(provider.classify_devices([], {"android_composite": True}), "ANDROID_USB_WITHOUT_ADB")
        for raw, state in (("device", "READY"), ("offline", "ADB_OFFLINE"), ("unauthorized", "ADB_UNAUTHORIZED"), ("recovery", "UNSUPPORTED_STATE")):
            self.assertEqual(provider.classify_devices(provider.parse_devices("fixture " + raw)), state)
        self.assertEqual(provider.classify_devices(provider.parse_devices("one device\ntwo device")), "MULTIPLE_DEVICES")

    def test_alias_collapse_and_ambiguity(self):
        expected = {"ro.serialno": "synthetic-stable", "ro.product.manufacturer": "FixtureVendor"}
        usb = {"state": "device", "transport": "usb", "_serial": "usb-fixture", "properties": expected}
        tcp = {**usb, "transport": "tcp", "_serial": "192.0.2.10:5555"}
        binding = provider.bind_identity([usb, tcp], expected)
        self.assertEqual(binding["state"], "IDENTITY_BOUND")
        self.assertEqual(binding["identity_ref"], provider.bind_identity([tcp], expected)["identity_ref"])
        self.assertEqual(provider.bind_identity([usb, {**tcp, "properties": {"ro.serialno": "other"}}], expected)["state"], "BLOCK")
        self.assertEqual(provider.bind_identity([usb, usb], expected)["state"], "BLOCK")
        self.assertEqual(provider.bind_identity([usb], {"ro.product.model": "A80"})["state"], "BLOCK")

    def test_lease_cross_process_contention(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with provider.provider_lease(directory):
                with self.assertRaisesRegex(RuntimeError, "PROVIDER_LEASE_BUSY"):
                    with provider.provider_lease(directory):
                        self.fail("contending process admitted")
                code = "from pathlib import Path; from harness.api.android_provider import provider_lease; import sys\ntry:\n with provider_lease(Path(sys.argv[1])): pass\nexcept RuntimeError:\n sys.exit(7)"
                child = subprocess.run([sys.executable, "-c", code, str(directory)], cwd=ROOT, capture_output=True)
                self.assertEqual(child.returncode, 7, child.stderr)
            self.assertFalse((directory / "android-provider.lock").exists())

    def binding(self):
        properties = {"ro.serialno": "synthetic-stable"}
        row = {"state": "device", "transport": "usb", "_serial": "usb-fixture", "properties": properties, "device_ip": "192.0.2.10"}
        return provider.bind_identity([row], properties)

    def test_transport_authority_and_identity_gate_no_commands(self):
        with patch.object(provider, "_run", side_effect=AssertionError("unauthorized command")):
            result = provider.certify_network(Path("fixture-adb"), self.binding(), "192.0.2.10", authorized=False, lease_dir=Path("unused"))
            self.assertEqual(result["result"], "BLOCK")

    def transaction(self, cleanup_failed=False, transition_timeout=False, tcp_mismatch=False):
        commands = []
        def run(argv, timeout=30):
            commands.append(argv)
            if "tcpip" in argv and transition_timeout:
                raise subprocess.TimeoutExpired(argv, timeout)
            rc = 1 if "usb" in argv and cleanup_failed else 0
            text = "connected to 192.0.2.10:5555" if "connect" in argv else "usb-fixture device" if "devices" in argv else ""
            return subprocess.CompletedProcess(argv, rc, text, "")
        def shell(adb, command, serial):
            text = "[ro.serialno]: [synthetic-stable]" if command == "getprop" else "inet 192.0.2.10/24"
            if tcp_mismatch and serial == "192.0.2.10:5555" and command == "getprop":
                text = "[ro.serialno]: [another-device]"
            return {"ok": True, "stdout": text}
        with tempfile.TemporaryDirectory() as temporary, patch.object(provider, "_run", side_effect=run), patch.object(provider, "collect_devices", return_value=[{"state": "device", "transport": "usb", "_serial": "usb-fixture"}]), patch.object(provider, "allowed_shell", side_effect=shell), patch.object(provider.socket, "create_connection", side_effect=ConnectionRefusedError), patch.object(provider.time, "sleep"):
            result = provider.certify_network(Path("fixture-adb"), self.binding(), "192.0.2.10", authorized=True, lease_dir=Path(temporary))
        for argv in commands:
            if "tcpip" in argv or "usb" in argv:
                self.assertIn("-s", argv)
            self.assertNotIn("-a", argv)
            if tcp_mismatch and "usb" in argv:
                self.assertNotIn("192.0.2.10:5555", argv)
        return result

    def test_complete_transport_and_cleanup(self):
        result = self.transaction()
        self.assertEqual(result["result"], "SUCCESS")
        self.assertEqual(result["cleanup"], "PROVEN")

    def test_cleanup_failure_never_success_and_partial_transition_reverts(self):
        self.assertEqual(self.transaction(cleanup_failed=True)["result"], "INCOMPLETE")
        result = self.transaction(transition_timeout=True)
        self.assertEqual(result["result"], "BLOCK")
        self.assertTrue(result["usb_revert_issued"])
        self.assertEqual(self.transaction(tcp_mismatch=True)["result"], "BLOCK")

    def test_loopback_server_refuses_unproven_binding(self):
        def run(argv, timeout=30):
            return subprocess.CompletedProcess(argv, 0, "0.0.0.0" if argv[0] == "powershell.exe" else "", "")
        with patch.object(provider, "_run", side_effect=run):
            with self.assertRaisesRegex(RuntimeError, "LOOPBACK_SERVER_NOT_PROVEN"):
                provider.collect_devices(Path("fixture-adb"), lease_held=True)

    def test_no_raw_shell_or_unselected_device(self):
        with self.assertRaises(RuntimeError):
            provider.allowed_shell(Path("fixture-adb"), "getprop", None)
        with self.assertRaises(RuntimeError):
            provider.allowed_shell(Path("fixture-adb"), "getprop; reboot", "synthetic")

    @unittest.skipUnless(os.name == "nt", "CMD execution requires Windows")
    def test_cmd_launcher_from_other_directory(self):
        fixture = ROOT / "Tests/survey/fixtures/android-provider/status-ready.fixture.json"
        with tempfile.TemporaryDirectory() as temporary:
            invocation = f'"{ROOT / "Run-SasAndroidProvider.cmd"}" status --fixture "{fixture}"'
            completed = subprocess.run('cmd.exe /d /s /c "' + invocation + '"', cwd=temporary, capture_output=True, text=True, timeout=30)
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertIn("SUCCESS: READY", completed.stdout)
            receipt = completed.stdout.split("Evidence: ", 1)[1].strip()
            result = json.loads(Path(receipt).read_text())
            self.assertEqual(result["proof"], "FIXTURE_ONLY")

    def test_source_admission_cannot_be_bypassed(self):
        from harness.api import android_provider_cli as cli
        with patch.object(cli, "admit_source", side_effect=RuntimeError("blocked")), patch.object(cli, "AndroidProvider", side_effect=AssertionError("unadmitted provider")):
            self.assertEqual(cli.main(["status", "--role", "ptop_lab"]), 2)

    def test_boundary_enforces_lifecycle_and_frontdoor(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("boundary", ROOT / "harness/validators/validate-sas-android-provider-boundary.py")
        validator = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(validator)
        original = json.loads((ROOT / "harness/api/sas-android-provider-boundary.v1.json").read_text())
        self.assertEqual(validator.validate_contract(original), [])
        for section, key in (("host_provider", "provider_lease_required_for_stateful_transport_changes"), ("cleanup", "temporary_forward_reverse_rules_must_be_removed"), ("cleanup", "temporary_device_payloads_must_be_removed"), ("public_surface", "operator_front_doors_delegate_to_repository_owned_cmd_or_sas_routes")):
            mutated = json.loads(json.dumps(original))
            mutated[section][key] = False
            self.assertIn(f"{section}.{key}", validator.validate_contract(mutated))

    def test_sealed_runtime_with_git_requires_selected_commit(self):
        from harness.api import android_provider_cli as cli
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = root / "runtime"
            runtime.mkdir()
            (runtime / ".git").mkdir()
            (runtime / "scripts").mkdir()
            (runtime / "scripts/Test-SasAutoLogonRuntimeSeal.ps1").write_text("synthetic")
            state = root / "SysAdminSuite/autologon-short-runtime.json"
            state.parent.mkdir()
            state.write_text(json.dumps({"runtime_root": str(runtime), "tracked_file_hashes": [{"path": p} for p in ("harness/api/android_provider.py", "harness/api/android_provider_cli.py", "Run-SasAndroidProvider.cmd")]}))
            calls = []
            def run(argv, **kwargs):
                calls.append(argv)
                return subprocess.CompletedProcess(argv, 0, "sealed", "")
            with patch.object(cli, "ROOT", runtime), patch.dict(os.environ, {"LOCALAPPDATA": str(root)}), patch.object(cli.subprocess, "run", side_effect=run):
                with self.assertRaisesRegex(RuntimeError, "SELECTED_REFRESHED_COMMIT_REQUIRED"):
                    cli.admit_source()
                self.assertEqual(cli.admit_source("a" * 40)["source_commit"], "a" * 40)
                self.assertIn("-ExpectedCommit", calls[-1])
                self.assertNotIn("git", calls[-1])
                with patch.object(cli.subprocess, "run", return_value=subprocess.CompletedProcess([], 10, "", "")):
                    with self.assertRaisesRegex(RuntimeError, "SOURCE_ADMISSION_FAILED"):
                        cli.admit_source("b" * 40)

    def test_migrated_hh_inventory_and_transport_authority(self):
        from harness.api import hh_cc_reader_adb_live as live
        from harness.api.hh_cc_reader_adb_control_plane import evaluate_control_plane
        def shell(adb, command, serial):
            text = "[ro.product.model]: [PAX A80]\n[ro.serialno]: [synthetic-stable]" if command == "getprop" else "inet 192.0.2.10/24 link/ether 02:00:00:00:00:01" if command == "ip addr" else "synthetic"
            return {"ok": True, "unsupported": False, "stdout_present": True, "stdout": text}
        host = {"chosen": Path("fixture-adb"), "owned": Path("fixture-adb"), "precedence": "owned", "version": "fixture", "path_adb": None}
        usb = {"android_composite": True, "adb_interface": True, "enumerated": True}
        rows = [{"serial_token": "SERIAL_PRESENT", "state": "device", "transport": "usb", "_serial": "synthetic-usb"}]
        with patch.object(live, "resolve_host", return_value=host), patch.object(live, "collect_usb", return_value=usb), patch.object(live, "collect_devices", return_value=rows), patch.object(live, "allowed_shell", side_effect=shell), patch.object(live, "certify_network", return_value={"result": "BLOCK", "cleanup": "NOT_REQUIRED"}) as cert:
            evidence = live.collect_live_evidence("inventory", expected_mac="02:00:00:00:00:01")
            self.assertEqual(len(evidence["inventory"]["commands"]), 7)
            self.assertTrue(evidence["identity"]["mac_correlated"])
            receipt = evaluate_control_plane(evidence)
            self.assertIsInstance(receipt, dict)
            live.collect_live_evidence("tcpip-cert", expected_mac="02:00:00:00:00:01")
            self.assertFalse(cert.call_args.kwargs["authorized"])
            live.collect_live_evidence("tcpip-cert", expected_mac="02:00:00:00:00:01", transport_authorized=True)
            self.assertTrue(cert.call_args.kwargs["authorized"])


if __name__ == "__main__":
    unittest.main()
