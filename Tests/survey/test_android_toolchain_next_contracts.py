#!/usr/bin/env python3
"""Adversarial contracts for the read-only Android toolchain Next operation (P141/P04).

Synthetic/static only. Does not claim Admin Box install, live Google fetch, device
readiness, or that Next is implemented. Several assertions intentionally FAIL until
W2 adds Next + repairs the schema operation enum (Bootstrap/Next).

Documented projection helper interface (W2 must implement):
  harness.api.android_toolchain_next.project_next_receipt(fixture: dict) -> dict
    - Returns a receipt shaped like sas-android-toolchain-result/v1 with
      operation == "Next".
    - Emits independent developer_track and sas_adb_track statuses.
    - Emits ordered actions with stable action_id, allowed_now, requires_authority,
      preconditions, proof_ref, command_owner, why_blocked.
    - Never invokes Apply, Bootstrap, or Repair; never mutates host state.
    - Never auto-promotes pin approval or host authority.
"""
from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api import android_platform_tools_pin as pins  # noqa: E402
from harness.api import android_provider as provider  # noqa: E402

SCHEMA = ROOT / "schemas/harness/android-toolchain-result.schema.json"
ENGINE = ROOT / "scripts/Invoke-SasAndroidToolchain.ps1"
ADMINBOX_PROFILE = ROOT / "Config/android-adminbox-toolchain-profile.json"
PTOP_PROFILE = ROOT / "Config/android-toolchain-profile.json"
PIN_CATALOG = ROOT / "configs/android-provider/sas-platform-tools-archive-pins.json"
PROVIDER = ROOT / "harness/api/android_provider.py"
NEXT_MODULE = ROOT / "harness/api/android_toolchain_next.py"
FIXTURES = ROOT / "Tests/Fixtures/android-toolchain-next"
TOOLCHAIN_FIXTURES = ROOT / "Tests/Fixtures/android-toolchain"
TRUSTBRIDGE_FIXTURES = ROOT / "Tests/Fixtures/android-trustbridge"

REQUIRED_NEXT_FIXTURES = {
    "missing-cli-studio-sdk",
    "inventory-success-incomplete",
    "host-authority-absent",
    "host-authority-malformed",
    "unapproved-archive-digest",
    "pin-zero-stale-hash",
    "protected-network-denied",
    "unsupported-role",
    "wrong-source-commit",
    "two-track-readiness-split",
    "next-readonly-no-mutation",
    "deterministic-action-order",
    "private-output-redaction",
    "rollback-preservation",
    "ptop-isolation",
}

TRACK_VALUES = {
    "VERIFIED",
    "NEEDS_INSTALL",
    "VERIFY_REQUIRED",
    "POLICY_BLOCKED",
    "UNKNOWN",
    "QUALIFIED",
    "NEEDS_APPROVAL",
    "NEEDS_PREPARE",
}

MUTATION_OPS = {"Apply", "Repair", "Bootstrap"}
READ_OPS = {"Inventory", "Plan", "Verify", "Next"}

PRIVACY_LEAKS = ("C:\\Users", "CheeksMcClappeth", "LPW003", "%USERPROFILE%", "%ONEDRIVE%")


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def w2_required(message: str) -> AssertionError:
    return AssertionError(f"W2_IMPLEMENTATION_REQUIRED: {message}")


def load_projection_helper():
    """Import the W2 Next projection helper or raise a clear gate failure."""
    try:
        from harness.api import android_toolchain_next as next_api
    except ImportError as exc:  # pragma: no cover - expected until W2 lands
        raise w2_required(
            "harness.api.android_toolchain_next missing "
            "(expected project_next_receipt)"
        ) from exc
    if not hasattr(next_api, "project_next_receipt"):
        raise w2_required("android_toolchain_next.project_next_receipt missing")
    return next_api


class AndroidToolchainNextContracts(unittest.TestCase):
    # ------------------------------------------------------------------ #
    # Fixture inventory / privacy (pass on this branch)
    # ------------------------------------------------------------------ #
    def test_next_fixture_catalog_privacy_and_coverage(self):
        names = {p.name.removesuffix(".fixture.json") for p in FIXTURES.glob("*.fixture.json")}
        self.assertTrue(REQUIRED_NEXT_FIXTURES <= names, sorted(names))
        for path in sorted(FIXTURES.glob("*.fixture.json")):
            data = load(path)
            self.assertTrue(data["synthetic"] is True, path.name)
            self.assertEqual(data["schema_version"], "sas-android-toolchain-next-fixture/v1")
            expectation = data["test_expectation"]
            self.assertEqual(expectation["operation"], "Next")
            self.assertTrue(expectation.get("must_not_mutate") is True, path.name)
            text = path.read_text(encoding="utf-8")
            for leak in PRIVACY_LEAKS:
                self.assertNotIn(leak.lower(), text.lower(), (path.name, leak))
            # Do not recreate or depend on the nineteen trustbridge fixtures.
            self.assertNotEqual(FIXTURES.resolve(), TRUSTBRIDGE_FIXTURES.resolve())

    # ------------------------------------------------------------------ #
    # Known discrepancy: schema enum omits Bootstrap (and Next) — FAIL
    # ------------------------------------------------------------------ #
    def test_schema_operation_enum_includes_bootstrap_and_next(self):
        """KNOWN DISCREPANCY: engine ValidateSet has Bootstrap; schema omits it.

        W2 must add Bootstrap and Next to schemas/harness/android-toolchain-result.schema.json
        while preserving additionalProperties: false.
        """
        schema = load(SCHEMA)
        ops = set(schema["properties"]["operation"]["enum"])
        missing = {"Bootstrap", "Next"} - ops
        self.assertFalse(
            missing,
            "schema operation enum missing %s (engine ValidateSet already includes Bootstrap; "
            "W2 must add Bootstrap and Next)" % sorted(missing),
        )
        self.assertFalse(schema.get("additionalProperties", True))

    def test_engine_validateset_bootstrap_vs_schema_drift_is_documented(self):
        """Regression floor: engine already accepts Bootstrap; schema must catch up."""
        engine = ENGINE.read_text(encoding="utf-8-sig")
        self.assertRegex(
            engine,
            r"ValidateSet\('Inventory','Plan','Apply','Verify','Repair','Bootstrap'\)",
        )
        schema_ops = set(load(SCHEMA)["properties"]["operation"]["enum"])
        self.assertIn("Bootstrap", re.findall(r"'(\w+)'", engine.split("ValidateSet")[1].split(")")[0]))
        # Failing assertion W2 must clear by extending the schema enum.
        self.assertIn("Bootstrap", schema_ops)

    # ------------------------------------------------------------------ #
    # Next operation presence — FAIL until W2
    # ------------------------------------------------------------------ #
    def test_engine_validateset_includes_next(self):
        engine = ENGINE.read_text(encoding="utf-8-sig")
        match = re.search(r"ValidateSet\(([^)]+)\)", engine)
        self.assertIsNotNone(match, "ValidateSet missing from engine")
        ops = {token.strip("'") for token in match.group(1).split(",")}
        self.assertIn("Next", ops, "W2 must add Next to engine ValidateSet")

    def test_adminbox_profile_allows_readonly_next(self):
        profile = load(ADMINBOX_PROFILE)
        allowed = set(profile["allowed_operations"])
        self.assertTrue(MUTATION_OPS <= allowed or "Bootstrap" in allowed)
        self.assertIn(
            "Next",
            allowed,
            "W2 must add read-only Next to Config/android-adminbox-toolchain-profile.json "
            "allowed_operations",
        )
        # Next must never be classified as a mutation op in fixture gates.
        engine = ENGINE.read_text(encoding="utf-8-sig")
        # Current mutation fixture gate must not list Next; when Next lands it stays read-only.
        self.assertNotRegex(engine, r"Operation -in @\('Apply','Repair','Bootstrap','Next'\)")

    def test_next_must_not_appear_in_mutation_fixture_gate(self):
        engine = ENGINE.read_text(encoding="utf-8-sig")
        self.assertIn("FIXTURE_MUTATION_FORBIDDEN", engine)
        # Document invariant: Next is read-only; mutation set is Apply/Repair/Bootstrap only.
        self.assertIn("$Operation -in @('Apply','Repair','Bootstrap')", engine)
        # Next is read-only and must never join the mutation forbidden set.
        mutation_gate = re.search(
            r"\$Operation -in @\('Apply','Repair','Bootstrap'(?:,'Next')?\)",
            engine,
        )
        self.assertIsNotNone(mutation_gate)
        self.assertNotIn("'Next'", mutation_gate.group(0))

    # ------------------------------------------------------------------ #
    # Projection helper + fixture-driven expectations — FAIL until W2
    # ------------------------------------------------------------------ #
    def test_projection_helper_module_exists(self):
        self.assertTrue(
            NEXT_MODULE.is_file(),
            "W2_IMPLEMENTATION_REQUIRED: create harness/api/android_toolchain_next.py",
        )
        load_projection_helper()

    def test_fixture_driven_next_projection_matches_expectations(self):
        next_api = load_projection_helper()
        for path in sorted(FIXTURES.glob("*.fixture.json")):
            with self.subTest(fixture=path.name):
                fixture = load(path)
                expected = fixture["test_expectation"]
                receipt = next_api.project_next_receipt(fixture)
                self.assertEqual(receipt["operation"], "Next")
                self.assertEqual(receipt["schema_version"], "sas-android-toolchain-result/v1")
                self.assertEqual(receipt.get("node_role"), expected["node_role"])
                self.assertFalse(receipt.get("operational_ready", True))
                self.assertEqual(receipt.get("inspection_status"), expected["inspection_status"])
                self.assertEqual(receipt.get("developer_track"), expected["developer_track"])
                self.assertEqual(receipt.get("sas_adb_track"), expected["sas_adb_track"])
                self.assertIn(receipt["developer_track"], TRACK_VALUES)
                self.assertIn(receipt["sas_adb_track"], TRACK_VALUES)
                for reason in expected.get("reasons", []):
                    self.assertIn(reason, receipt.get("reason_codes", []), (path.name, reason, receipt))
                actions = receipt.get("actions") or []
                action_ids = [row.get("action_id") for row in actions]
                if expected.get("action_order_strict") or expected.get("action_ids"):
                    self.assertEqual(action_ids, expected["action_ids"], path.name)
                for label in expected.get("forbid_labels", []):
                    blob = json.dumps(receipt)
                    self.assertNotIn(label, blob, (path.name, label))
                if expected.get("forbid_both_tracks_ready"):
                    both_ready = (
                        receipt.get("developer_track") in {"VERIFIED", "QUALIFIED"}
                        and receipt.get("sas_adb_track") in {"QUALIFIED", "VERIFIED"}
                    )
                    self.assertFalse(both_ready, path.name)
                if expected.get("tracks_must_differ"):
                    self.assertNotEqual(
                        receipt.get("developer_track"),
                        receipt.get("sas_adb_track"),
                        path.name,
                    )
                for leak in expected.get("receipt_must_not_contain", []):
                    self.assertNotIn(leak.lower(), json.dumps(receipt).lower(), path.name)
                # Read-only: projection must not claim mutation proofs.
                for forbidden in ("PREPARED", "INSTALLED", "MUTATED"):
                    self.assertNotIn(forbidden, receipt.get("proof") or [])

    def test_next_projection_never_calls_apply_or_bootstrap(self):
        next_api = load_projection_helper()
        fixture = load(FIXTURES / "next-readonly-no-mutation.fixture.json")
        # Monkeypatch-style: if helper exposes side-effect hooks, they must stay unused.
        called = {"Apply": 0, "Bootstrap": 0, "Repair": 0}

        def _deny(name):
            def _inner(*_a, **_k):
                called[name] += 1
                raise AssertionError(f"Next must not call {name}")

            return _inner

        for name in list(called):
            if hasattr(next_api, name) or hasattr(next_api, name.lower()):
                setattr(next_api, name, _deny(name))
        receipt = next_api.project_next_receipt(fixture)
        self.assertEqual(sum(called.values()), 0, called)
        self.assertEqual(receipt["operation"], "Next")
        for action in receipt.get("actions") or []:
            if action.get("action_id") == "SUGGEST_BOOTSTRAP_SAS_PLATFORM_TOOLS":
                self.assertFalse(action.get("allowed_now", True))
                self.assertTrue(action.get("requires_authority", False))

    # ------------------------------------------------------------------ #
    # Existing floors that already pass (inventory ≠ ready, pins, roles)
    # ------------------------------------------------------------------ #
    def test_inventory_success_is_not_operational_ready(self):
        """Inventory may SUCCESS with missing CLI/Studio; that is not installed proof."""
        shell = shutil.which("pwsh")
        self.assertTrue(shell, "PowerShell 7 required for executable fixture gate")
        fixture_path = FIXTURES / "inventory-success-incomplete.fixture.json"
        # Engine fixture shape uses inventory + synthetic; strip next-only envelope fields
        # by writing a minimal toolchain-compatible synthetic fixture.
        payload = load(fixture_path)
        minimal = {"synthetic": True, "inventory": payload["inventory"]}
        with tempfile.TemporaryDirectory(prefix="sas-next-inv-") as output:
            out = Path(output)
            fixture = out / "incomplete.fixture.json"
            fixture.write_text(json.dumps(minimal), encoding="utf-8")
            command = [
                shell,
                "-NoProfile",
                "-File",
                str(ENGINE),
                "-FixturePath",
                str(fixture),
                "-Operation",
                "Inventory",
                "-NodeRole",
                "adminbox_reference",
                "-OutputRoot",
                str(out / "receipts"),
            ]
            process = subprocess.run(command, capture_output=True, text=True, timeout=60)
            receipts = list((out / "receipts").glob("receipt-*.json"))
            self.assertEqual(len(receipts), 1, (process.returncode, process.stdout, process.stderr))
            receipt = load(receipts[0])
            self.assertEqual(process.returncode, 0, receipt)
            self.assertEqual(receipt["result"], "SUCCESS")
            self.assertIn("MISSING_ANDROID_CLI", receipt["reason_codes"])
            self.assertIn("MISSING_ANDROID_STUDIO", receipt["reason_codes"])
            self.assertEqual(receipt["proof"], ["FIXTURE_ONLY"])
            # Invariant consumed by Next: SUCCESS ≠ operational ready / installed.
            self.assertNotEqual(receipt["reason_codes"], [])

    def test_missing_cli_studio_sdk_inventory_reasons(self):
        shell = shutil.which("pwsh")
        self.assertTrue(shell, "PowerShell 7 required")
        payload = load(FIXTURES / "missing-cli-studio-sdk.fixture.json")
        minimal = {"synthetic": True, "inventory": payload["inventory"]}
        with tempfile.TemporaryDirectory(prefix="sas-next-miss-") as output:
            out = Path(output)
            fixture = out / "missing.fixture.json"
            fixture.write_text(json.dumps(minimal), encoding="utf-8")
            command = [
                shell,
                "-NoProfile",
                "-File",
                str(ENGINE),
                "-FixturePath",
                str(fixture),
                "-Operation",
                "Inventory",
                "-NodeRole",
                "adminbox_reference",
                "-OutputRoot",
                str(out / "receipts"),
            ]
            process = subprocess.run(command, capture_output=True, text=True, timeout=60)
            receipt = load(next((out / "receipts").glob("receipt-*.json")))
            self.assertEqual(process.returncode, 0, receipt)
            self.assertEqual(receipt["result"], "SUCCESS")
            for reason in ("MISSING_ANDROID_CLI", "MISSING_ANDROID_STUDIO"):
                self.assertIn(reason, receipt["reason_codes"])

    def test_tracked_pin_catalog_zero_hash_fails_closed(self):
        catalog = load(PIN_CATALOG)
        self.assertTrue(catalog["pins"])
        pin = catalog["pins"][0]
        self.assertEqual(pin["expected_archive_sha256"], "0" * 64)
        self.assertEqual(pin["promotion_status"], "blocked_pending_independent_sha256_pin")
        with self.assertRaisesRegex(pins.PinResolutionError, "QUALIFICATION_AUTHORITY_REQUIRED"):
            pins.resolve("adminbox_reference", catalog_path=PIN_CATALOG)

    def test_approved_vs_unapproved_archive_digest(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "platform-tools_r36.0.0-win.zip"
            with zipfile.ZipFile(archive, "w") as zipped:
                for name in provider.REQUIRED_COMPONENTS:
                    payload = "Pkg.Revision=36.0.0\n" if name == "source.properties" else "synthetic"
                    zipped.writestr("platform-tools/" + name, payload)
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            url = "https://dl.google.com/android/repository/platform-tools_r36.0.0-win.zip"
            approved = root / "approved.json"
            approved.write_text(
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
                                "approval_reference": "REVIEW-FIXTURE-NEXT-1",
                                "allowed_node_roles": ["adminbox_reference"],
                                "promotion_status": "approved_for_provider_prepare",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            pin = pins.resolve("adminbox_reference", catalog_path=approved)
            self.assertEqual(pin["expected_archive_sha256"], digest)

            unapproved = root / "unapproved.json"
            unapproved.write_text(
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
                                "approval_reference": "PENDING",
                                "allowed_node_roles": ["adminbox_reference"],
                                "promotion_status": "blocked_pending_independent_sha256_pin",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(pins.PinResolutionError, "QUALIFICATION_AUTHORITY_REQUIRED"):
                pins.resolve("adminbox_reference", catalog_path=unapproved)

            zero = root / "zero.json"
            zero.write_text(
                json.dumps(
                    {
                        "schema_version": pins.SCHEMA_VERSION,
                        "catalog_id": "t",
                        "pins": [
                            {
                                "artifact_id": pins.ARTIFACT_ID,
                                "version": "36.0.0",
                                "acquisition_url": url,
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

    def test_unsupported_role_fails_closed_on_inventory(self):
        shell = shutil.which("pwsh")
        self.assertTrue(shell, "PowerShell 7 required")
        with tempfile.TemporaryDirectory(prefix="sas-next-role-") as output:
            out = Path(output)
            command = [
                shell,
                "-NoProfile",
                "-File",
                str(ENGINE),
                "-FixturePath",
                str(TOOLCHAIN_FIXTURES / "healthy.fixture.json"),
                "-Operation",
                "Inventory",
                "-NodeRole",
                "unsupported_synthetic_role",
                "-OutputRoot",
                str(out),
            ]
            process = subprocess.run(command, capture_output=True, text=True, timeout=60)
            receipt = load(next(out.glob("receipt-*.json")))
            self.assertEqual(process.returncode, 2, receipt)
            self.assertEqual(receipt["result"], "BLOCK")
            self.assertIn("NODE_ROLE_MISMATCH", receipt["reason_codes"])

    def test_protected_network_reason_vocabulary_is_stable(self):
        fixture = load(FIXTURES / "protected-network-denied.fixture.json")
        self.assertEqual(fixture["next_inputs"]["network_class"], "protected_denied")
        self.assertIn("PROTECTED_NETWORK_DENIED", fixture["test_expectation"]["reasons"])
        # Engine/bootstrap trust-bridge already documents the typed reason.
        engine = ENGINE.read_text(encoding="utf-8-sig")
        # May not yet appear in engine Next path; vocabulary must remain available to W2.
        self.assertIn(
            "PROTECTED_NETWORK_DENIED",
            (TRUSTBRIDGE_FIXTURES / "protected-network-denied.fixture.json").read_text(encoding="utf-8"),
        )
        self.assertTrue(engine)  # engine present for W2 to wire typed reason into Next

    def test_wrong_source_commit_expectation_is_typed(self):
        fixture = load(FIXTURES / "wrong-source-commit.fixture.json")
        self.assertFalse(fixture["next_inputs"]["source_commit_match"])
        self.assertEqual(fixture["test_expectation"]["reasons"], ["SOURCE_COMMIT_MISMATCH"])

    def test_host_authority_absent_and_malformed_expectations(self):
        absent = load(FIXTURES / "host-authority-absent.fixture.json")
        malformed = load(FIXTURES / "host-authority-malformed.fixture.json")
        self.assertEqual(absent["next_inputs"]["host_authority_status"], "ABSENT")
        self.assertIn("ADMINBOX_PROFILE_AUTHORITY_REQUIRED", absent["test_expectation"]["reasons"])
        self.assertEqual(malformed["next_inputs"]["host_authority_status"], "MALFORMED")
        self.assertIn("ADMINBOX_PROFILE_AUTHORITY_INVALID", malformed["test_expectation"]["reasons"])
        engine = ENGINE.read_text(encoding="utf-8-sig")
        self.assertIn("ADMINBOX_PROFILE_AUTHORITY_REQUIRED", engine)
        self.assertIn("ADMINBOX_PROFILE_AUTHORITY_INVALID", engine)

    # ------------------------------------------------------------------ #
    # Rollback preservation language + PTop isolation (pass now)
    # ------------------------------------------------------------------ #
    def test_rollback_preservation_language_in_provider(self):
        text = PROVIDER.read_text(encoding="utf-8")
        self.assertIn("Preserve the previous runtime for explicit rollback", text)
        self.assertIn("no destructive cleanup", text)
        self.assertIn("PRIOR_RUNTIME_BACKUP_REQUIRES_REVIEW", text)
        fixture = load(FIXTURES / "rollback-preservation.fixture.json")
        for fragment in fixture["test_expectation"]["rollback_language_required"]:
            self.assertIn(fragment.lower(), text.lower(), fragment)

    def test_ptop_behavior_unchanged_adminbox_isolation(self):
        engine = ENGINE.read_text(encoding="utf-8-sig")
        self.assertIn("Assert-PTopProfile", engine)
        self.assertIn("PTOP_PROFILE_AUTHORITY_INVALID", engine)
        self.assertIn("Assert-HostProfileForRole", engine)
        self.assertIn("@('ptop_lab','adminbox_reference')", engine)
        ptop = load(PTOP_PROFILE)
        admin = load(ADMINBOX_PROFILE)
        self.assertEqual(ptop["node_role"], "ptop_lab")
        self.assertEqual(admin["node_role"], "adminbox_reference")
        self.assertNotEqual(ptop["node_role"], admin["node_role"])
        # PTop desired-state authority stays on its own profile file.
        self.assertTrue(PTOP_PROFILE.is_file())
        self.assertTrue((ROOT / "Tests/survey/test_android_toolchain_contracts.py").is_file())
        isolation = load(FIXTURES / "ptop-isolation.fixture.json")
        self.assertTrue(isolation["test_expectation"]["must_preserve_ptop_authority_gate"])

    def test_two_track_readiness_fixture_keeps_tracks_independent(self):
        fixture = load(FIXTURES / "two-track-readiness-split.fixture.json")
        expected = fixture["test_expectation"]
        self.assertEqual(expected["developer_track"], "VERIFIED")
        self.assertEqual(expected["sas_adb_track"], "NEEDS_APPROVAL")
        self.assertTrue(expected["tracks_must_differ"])
        self.assertTrue(expected["forbid_both_tracks_ready"])
        self.assertNotEqual(expected["developer_track"], expected["sas_adb_track"])

    def test_deterministic_action_order_fixture_is_strict(self):
        fixture = load(FIXTURES / "deterministic-action-order.fixture.json")
        expected = fixture["test_expectation"]
        self.assertTrue(expected["action_order_strict"])
        self.assertEqual(
            expected["action_ids"],
            [
                "REQUEST_HOST_PROFILE_AUTHORITY",
                "PREPARE_PIN_APPROVAL_PACKET",
                "INSTALL_DEVELOPER_STACK",
            ],
        )

    def test_does_not_recreate_trustbridge_nineteen(self):
        # Ownership boundary: Next fixtures live in a new directory; #540 trustbridge catalog untouched.
        trust_names = {p.name for p in TRUSTBRIDGE_FIXTURES.glob("*.fixture.json")}
        self.assertGreaterEqual(len(trust_names), 19)
        self.assertEqual(FIXTURES.name, "android-toolchain-next")
        self.assertNotEqual(FIXTURES.resolve(), TRUSTBRIDGE_FIXTURES.resolve())
        for path in FIXTURES.glob("*.fixture.json"):
            self.assertEqual(load(path)["schema_version"], "sas-android-toolchain-next-fixture/v1")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
