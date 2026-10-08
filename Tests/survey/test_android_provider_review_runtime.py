"""Runtime review regressions: verified archive bytes and target profile gates."""
from __future__ import annotations

import copy
import json
import sys
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from harness.api import android_provider as provider

PROFILE = {
    "schema_version": "sas-android-target-profile/v1",
    "organization": {"id": "synthetic-organization", "status": "RESOLVED", "evidence_ref": "synthetic-approval"},
    "site": {"id": "synthetic-site", "organization_id": "synthetic-organization", "status": "RESOLVED", "evidence_ref": "synthetic-site-approval"},
    "equipment": {"id": "synthetic-android", "status": "RESOLVED", "evidence_ref": "synthetic-equipment-approval", "device_class": "android"},
    "allowed_operations": ["tcpip-cert"],
}


class RuntimeReviewTests(unittest.TestCase):
    def write_archive(self, path, binary):
        with zipfile.ZipFile(path, "w") as archive:
            for component in provider.REQUIRED_COMPONENTS:
                archive.writestr("platform-tools/" + component, "Pkg.Revision=36.0.0\n" if component == "source.properties" else binary)

    def test_extracts_same_verified_bytes_when_source_path_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "approved.zip"
            self.write_archive(source, "approved-binary")
            approved_sha = provider.sha256(source)
            def swap_after_verification(adb):
                self.write_archive(source, "replaced-binary")
                return "STOPPED"
            with patch.object(provider, "HOST_LEASE_DIR", root / "lease"), patch.object(provider, "host_server_state", side_effect=swap_after_verification):
                manifest = provider.prepare_bundle(source, approved_sha, root / "installed")
            self.assertNotEqual(provider.sha256(source), approved_sha)
            self.assertEqual((root / "installed/adb.exe").read_text(), "approved-binary")
            self.assertEqual(manifest["sha256"], approved_sha)
            self.assertEqual(provider.verify_bundle(root / "installed")["state"], "READY")

    def test_bundle_and_manifest_replacement_cannot_replace_preparation_anchor(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "approved.zip"
            self.write_archive(source, "approved-binary")
            installed = root / "installed"
            with patch.object(provider, "HOST_LEASE_DIR", root / "lease"), patch.object(provider, "host_server_state", return_value="STOPPED"):
                provider.prepare_bundle(source, provider.sha256(source), installed)
            anchor = provider.qualification_anchor(installed)
            original_anchor = anchor.read_bytes()
            (installed / "adb.exe").write_text("replaced-binary")
            manifest_path = installed / provider.MANIFEST
            manifest = json.loads(manifest_path.read_text())
            manifest["component_manifest"]["adb.exe"] = provider.sha256(installed / "adb.exe")
            manifest_path.write_text(json.dumps(manifest))
            self.assertEqual(provider.verify_bundle(installed)["state"], "ATTESTATION_MISMATCH")
            self.assertEqual(anchor.read_bytes(), original_anchor)
            with patch.object(provider, "_run", side_effect=AssertionError("unattested binary executed")):
                self.assertIsNone(provider.resolve_host(installed)["chosen"])

    def test_anchor_write_failure_restores_old_runtime_and_anchor(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "approved.zip"
            installed = root / "installed"
            self.write_archive(source, "old-binary")
            with patch.object(provider, "HOST_LEASE_DIR", root / "lease"), patch.object(provider, "host_server_state", return_value="STOPPED"):
                provider.prepare_bundle(source, provider.sha256(source), installed)
                anchor = provider.qualification_anchor(installed)
                old_anchor = anchor.read_bytes()
                self.write_archive(source, "new-binary")
                write_text = Path.write_text
                def fail_anchor(path, *args, **kwargs):
                    if path == anchor:
                        raise OSError("synthetic anchor write failure")
                    return write_text(path, *args, **kwargs)
                with patch.object(Path, "write_text", fail_anchor), self.assertRaises(OSError):
                    provider.prepare_bundle(source, provider.sha256(source), installed)
                self.assertEqual((installed / "adb.exe").read_text(), "old-binary")
                self.assertEqual(anchor.read_bytes(), old_anchor)
                self.assertEqual(provider.verify_bundle(installed)["state"], "READY")
                self.assertFalse(provider.qualification_anchor(root / "installed.previous").exists())
                provider.prepare_bundle(source, provider.sha256(source), installed)
            self.assertEqual(provider.verify_bundle(root / "installed.previous")["state"], "READY")
            self.assertEqual(provider.qualification_anchor(root / "installed.previous").read_bytes(), old_anchor)

    def test_connect_timeout_remains_timeout_through_cleanup(self):
        props = {"ro.serialno": "synthetic-stable"}
        row = {"state": "device", "transport": "usb", "_serial": "synthetic-usb", "properties": props, "device_ip": "192.0.2.10"}
        binding = provider.bind_identity([row], props)
        def run(argv, timeout=30):
            if "connect" in argv:
                raise subprocess.TimeoutExpired(argv, timeout)
            return subprocess.CompletedProcess(argv, 0, "synthetic-usb device" if "devices" in argv else "", "")
        def shell(adb, command, serial):
            return {"ok": True, "stdout": "[ro.serialno]: [synthetic-stable]" if command == "getprop" else "inet 192.0.2.10/24"}
        with tempfile.TemporaryDirectory() as temporary, patch.object(provider, "verify_bundle", return_value={"state": "READY"}), patch.object(provider, "collect_devices", return_value=[row]), patch.object(provider, "allowed_shell", side_effect=shell), patch.object(provider, "_run", side_effect=run), patch.object(provider.socket, "create_connection", side_effect=ConnectionRefusedError), patch.object(provider.time, "sleep"):
            result = provider.certify_network(Path("synthetic-adb"), binding, "192.0.2.10", authorized=True, lease_dir=Path(temporary), profile_authority=PROFILE)
        self.assertEqual(result["connect_result"], "timeout")
        self.assertEqual(result["result"], "BLOCK")
        self.assertEqual(result["cleanup"], "PROVEN")

    def test_connect_refusal_requires_explicit_evidence(self):
        endpoint = "192.0.2.10:5555"
        cases = [
            (0, "connected to " + endpoint, "", "success"),
            (0, "already connected to " + endpoint, "", "success"),
            (0, "connected to 192.0.2.11:5555", "", "inconclusive"),
            (0, "unexpected response", "", "inconclusive"),
            (1, "", "cannot connect: network unreachable", "error"),
            (1, "", "authentication failed", "error"),
            (1, "", "connection refused", "refused"),
            (0, "cannot connect: target machine actively refused it (10061)", "", "refused"),
        ]
        for rc, stdout, stderr, expected in cases:
            with self.subTest(expected=expected, stdout=stdout, stderr=stderr):
                completed = subprocess.CompletedProcess([], rc, stdout, stderr)
                self.assertEqual(provider.classify_connect_result(completed, endpoint), expected)

    def test_profile_requires_both_layers_explicit_operation_and_site_relationship(self):
        self.assertTrue(provider.validate_profile_authority(PROFILE))
        cases = [None, {}, {**PROFILE, "equipment": {}}, {**PROFILE, "allowed_operations": []}]
        for section, field, value in (("organization", "status", "UNKNOWN"), ("site", "organization_id", "another-org"), ("site", "id", "unknown"), ("equipment", "device_class", "shared-workstation"), ("equipment", "evidence_ref", "")):
            item = copy.deepcopy(PROFILE)
            item[section][field] = value
            cases.append(item)
        for value in cases:
            with self.subTest(value=value):
                self.assertFalse(provider.validate_profile_authority(value))

    def test_authorized_boolean_and_identity_never_replace_profiles(self):
        props = {"ro.serialno": "synthetic-stable"}
        binding = provider.bind_identity([{"state": "device", "transport": "usb", "_serial": "synthetic-usb", "properties": props, "device_ip": "192.0.2.10"}], props)
        for authority in (None, {}, {**PROFILE, "equipment": {}}):
            with patch.object(provider, "_run", side_effect=AssertionError("profile gate bypassed")), patch.object(provider, "provider_lease", side_effect=AssertionError("profile gate bypassed")):
                result = provider.certify_network(Path("synthetic-adb"), binding, "192.0.2.10", authorized=True, lease_dir=Path("unused"), profile_authority=authority)
            self.assertEqual(result["result"], "BLOCK")
            self.assertEqual(result["reason"], "RESOLVED_TARGET_PROFILES_REQUIRED")
            self.assertEqual(result["authority"], "MUTATION_GATED")
            self.assertFalse(result["tcpip_issued"])


if __name__ == "__main__":
    unittest.main()
