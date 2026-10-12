#!/usr/bin/env python3
"""Adversarial and positive contracts for the Platform-Tools trust-bridge pin catalog.

Synthetic/static only. Does not claim Admin Box install, live Google fetch, or
device readiness. Empty/blocked catalogs must fail closed before prepare.
"""
from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
import sys

sys.path.insert(0, str(ROOT))
from harness.api import android_platform_tools_pin as pins
from harness.api import android_provider as provider

CATALOG = ROOT / "configs/android-provider/sas-platform-tools-archive-pins.json"
SCHEMA = ROOT / "schemas/harness/sas-platform-tools-archive-pins.schema.json"
ENGINE = ROOT / "scripts/Invoke-SasAndroidToolchain.ps1"
ADMINBOX_PROFILE = ROOT / "Config/android-adminbox-toolchain-profile.json"
DECISION = ROOT / "docs/plans/p95-android-platform-tools-trust-bridge-20261012.decision.md"


class TrustBridgeContracts(unittest.TestCase):
    def test_tracked_catalog_is_blocked_pending_independent_approval(self):
        catalog = json.loads(CATALOG.read_text(encoding="utf-8-sig"))
        self.assertEqual(catalog["schema_version"], pins.SCHEMA_VERSION)
        self.assertTrue(SCHEMA.is_file())
        self.assertTrue(DECISION.is_file())
        self.assertTrue(catalog["pins"], "placeholder pin documents intended version")
        for pin in catalog["pins"]:
            self.assertEqual(pin["promotion_status"], "blocked_pending_independent_sha256_pin")
            self.assertNotIn("platform-tools-latest-windows.zip", pin["acquisition_url"])
        with self.assertRaisesRegex(pins.PinResolutionError, "QUALIFICATION_AUTHORITY_REQUIRED"):
            pins.resolve("adminbox_reference", catalog_path=CATALOG)

    def test_empty_and_role_mismatched_pins_fail_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            empty = root / "empty.json"
            empty.write_text(
                json.dumps({"schema_version": pins.SCHEMA_VERSION, "catalog_id": "t", "pins": []}),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(pins.PinResolutionError, "QUALIFICATION_AUTHORITY_REQUIRED"):
                pins.resolve("adminbox_reference", catalog_path=empty)

            blocked = root / "blocked.json"
            blocked.write_text(
                json.dumps(
                    {
                        "schema_version": pins.SCHEMA_VERSION,
                        "catalog_id": "t",
                        "pins": [
                            {
                                "artifact_id": pins.ARTIFACT_ID,
                                "version": "37.0.1",
                                "acquisition_url": "https://dl.google.com/android/repository/platform-tools_r37.0.1-win.zip",
                                "expected_archive_sha256": "a" * 64,
                                "approval_reference": "REVIEW-1",
                                "allowed_node_roles": ["ptop_lab"],
                                "promotion_status": "approved_for_provider_prepare",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(pins.PinResolutionError, "SOURCE_POLICY_DENIED"):
                pins.resolve("adminbox_reference", catalog_path=blocked)

    def test_mutable_latest_and_zero_digest_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            latest = root / "latest.json"
            latest.write_text(
                json.dumps(
                    {
                        "schema_version": pins.SCHEMA_VERSION,
                        "catalog_id": "t",
                        "pins": [
                            {
                                "artifact_id": pins.ARTIFACT_ID,
                                "version": "37.0.1",
                                "acquisition_url": "https://dl.google.com/android/repository/platform-tools-latest-windows.zip",
                                "expected_archive_sha256": "a" * 64,
                                "approval_reference": "REVIEW-1",
                                "allowed_node_roles": ["adminbox_reference"],
                                "promotion_status": "approved_for_provider_prepare",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            # Schema-invalid URL: resolver must fail closed even if promotion claims approved.
            with self.assertRaisesRegex(pins.PinResolutionError, "SOURCE_POLICY_DENIED"):
                pins.resolve("adminbox_reference", catalog_path=latest)

            zero = root / "zero.json"
            zero.write_text(
                json.dumps(
                    {
                        "schema_version": pins.SCHEMA_VERSION,
                        "catalog_id": "t",
                        "pins": [
                            {
                                "artifact_id": pins.ARTIFACT_ID,
                                "version": "37.0.1",
                                "acquisition_url": "https://dl.google.com/android/repository/platform-tools_r37.0.1-win.zip",
                                "expected_archive_sha256": "0" * 64,
                                "approval_reference": "REVIEW-1",
                                "allowed_node_roles": ["adminbox_reference"],
                                "promotion_status": "approved_for_provider_prepare",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(pins.PinResolutionError, "INDEPENDENT_APPROVAL_REQUIRED"):
                pins.resolve("adminbox_reference", catalog_path=zero)

    def test_approved_pin_resolves_and_prepare_records_true_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "platform-tools_r36.0.0-win.zip"
            with zipfile.ZipFile(archive, "w") as zipped:
                for name in provider.REQUIRED_COMPONENTS:
                    payload = "Pkg.Revision=36.0.0\n" if name == "source.properties" else "synthetic-binary"
                    zipped.writestr("platform-tools/" + name, payload)
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            catalog = root / "approved.json"
            url = "https://dl.google.com/android/repository/platform-tools_r36.0.0-win.zip"
            catalog.write_text(
                json.dumps(
                    {
                        "schema_version": pins.SCHEMA_VERSION,
                        "catalog_id": "t",
                        "pins": [
                            {
                                "artifact_id": pins.ARTIFACT_ID,
                                "version": "36.0.0",
                                "acquisition_url": url,
                                "expected_archive_sha256": digest,
                                "approval_reference": "REVIEW-FIXTURE-1",
                                "allowed_node_roles": ["adminbox_reference"],
                                "promotion_status": "approved_for_provider_prepare",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            pin = pins.resolve("adminbox_reference", catalog_path=catalog)
            self.assertEqual(pin["expected_archive_sha256"], digest)
            destination = root / "owned"
            with patch.object(provider, "HOST_LEASE_DIR", root / "lease"), patch.object(
                provider, "host_server_state", return_value="STOPPED"
            ):
                manifest = provider.prepare_bundle(archive, digest, destination, source=pin["acquisition_url"])
            self.assertEqual(manifest["source"], url)
            self.assertEqual(provider.verify_bundle(destination)["state"], "READY")
            with self.assertRaisesRegex(RuntimeError, "ARCHIVE_HASH_MISMATCH"):
                provider.prepare_bundle(archive, "b" * 64, root / "other", source=url)

    def test_engine_bootstrap_source_contract_and_no_mutable_latest_apply(self):
        text = ENGINE.read_text(encoding="utf-8-sig")
        self.assertIn("Bootstrap", text)
        self.assertIn("android_platform_tools_pin", text)
        self.assertIn("QUALIFICATION_AUTHORITY_REQUIRED", text)
        self.assertIn("--archive-source", text)
        self.assertNotIn("platform-tools-latest-windows.zip", text)
        profile = json.loads(ADMINBOX_PROFILE.read_text(encoding="utf-8-sig"))
        self.assertIn("Bootstrap", profile["allowed_operations"])
        # Existing PTop regression floor remains registered and loadable.
        self.assertTrue((ROOT / "Tests/survey/test_android_toolchain_contracts.py").is_file())
        self.assertTrue((ROOT / "Tests/survey/test_android_provider_implementation.py").is_file())
        self.assertIn("Assert-PTopProfile", text)

    def test_winget_or_sidecar_alone_cannot_approve(self):
        # Informational WinGet SHA without approved promotion_status must not resolve.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog = root / "winget-only.json"
            catalog.write_text(
                json.dumps(
                    {
                        "schema_version": pins.SCHEMA_VERSION,
                        "catalog_id": "t",
                        "pins": [
                            {
                                "artifact_id": pins.ARTIFACT_ID,
                                "version": "37.0.1",
                                "acquisition_url": "https://dl.google.com/android/repository/platform-tools_r37.0.1-win.zip",
                                "expected_archive_sha256": "45f4d63113e895ebde0c90f194099a4676b6ac653bd28d54314a9e022bbc1a99",
                                "approval_reference": "PENDING-WINGET-CANDIDATE",
                                "allowed_node_roles": ["adminbox_reference"],
                                "promotion_status": "blocked_pending_independent_sha256_pin",
                                "acquisition_evidence": "winget Google.PlatformTools 37.0.1 candidate only",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(pins.PinResolutionError, "QUALIFICATION_AUTHORITY_REQUIRED"):
                pins.resolve("adminbox_reference", catalog_path=catalog)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
