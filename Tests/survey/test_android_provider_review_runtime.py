"""Runtime review regressions: verified archive bytes and target profile gates."""
from __future__ import annotations

import copy
import sys
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
