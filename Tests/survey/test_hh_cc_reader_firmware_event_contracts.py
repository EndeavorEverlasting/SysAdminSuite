#!/usr/bin/env python3
"""Fail-closed contracts for SAS hh-cc-reader-firmware-event/v1 producer."""
from __future__ import annotations

import ast
import json
import subprocess
import sys
import tempfile
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_firmware_event import (  # noqa: E402
    SCHEMA,
    export_firmware_event,
    fingerprint_payload,
    write_event,
)
from harness.api.hh_cc_reader_firmware_roundtrip import (  # noqa: E402
    compare_roundtrip_states,
    evaluate_outdated_eligibility,
    evaluate_restore_path,
    freeze_baseline,
    resolve_target_identity,
)

MODULE = ROOT / "harness/api/hh_cc_reader_firmware_event.py"
LAUNCHER = ROOT / "Export-HHCCReaderFirmwareEvent.cmd"
SCHEMA_PATH = ROOT / "schemas/harness/hh-cc-reader-firmware-event.schema.json"
GOLDEN = ROOT / "docs/examples/hh-cc-reader-firmware-event.golden.json"
BLOCKED_FIXTURE = ROOT / "docs/examples/hh-cc-reader-firmware-event.blocked-progress.json"
BUNDLE_GOLDEN = ROOT / "docs/examples/hh-cc-reader-firmware-event.bundle.golden.json"
ROUNDTRIP_MODULE = ROOT / "harness/api/hh_cc_reader_firmware_roundtrip.py"

LIVE_FORBIDDEN = (
    "1240473751",
    "C8-40-52-3C-93-BA",
    "C840523C93BA",
    "192.168.1.68",
    "10.217.101.192",
)


def _unique_identity(**overrides):
    base = {
        "source_serial": "SYNTH-SERIAL-001",
        "source_name": "SYNTH-READER-A",
        "expected_mac": "AA-BB-CC-DD-EE-01",
        "live_mac": "AA-BB-CC-DD-EE-01",
        "live_ipv4": "192.0.2.10",
        "probe_mac_match": True,
        "identity_conflicts": [],
    }
    base.update(overrides)
    return resolve_target_identity(base)


def _locked_baseline(identity=None):
    identity = identity or _unique_identity()
    observation = {
        "source_serial": identity["source_serial"],
        "source_name": identity["source_name"],
        "expected_mac": identity["expected_mac"],
        "live_mac": identity["live_mac"],
        "live_ipv4": identity["live_ipv4"],
        "probe_mac_match": True,
        "identity_proof_state": "UNIQUE_TARGET_RESOLVED",
        "current_firmware_value": "2.0.15.260410",
        "target_firmware_value": "2.0.15.260522",
        "health_status": "online",
        "captured_at": "2026-10-03T00:01:00Z",
    }
    return freeze_baseline(observation, identity)


def test_tracked_surfaces_exist():
    assert MODULE.is_file()
    assert LAUNCHER.is_file()
    assert SCHEMA_PATH.is_file()
    assert GOLDEN.is_file()
    assert BLOCKED_FIXTURE.is_file()
    assert BUNDLE_GOLDEN.is_file()


def test_schema_const_and_producer_metadata():
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    assert schema["properties"]["schema"]["const"] == SCHEMA
    event = export_firmware_event({"identity": _unique_identity()})
    assert event["schema"] == SCHEMA
    assert event["producer"]["repository"] == "EndeavorEverlasting/SysAdminSuite"
    assert event["producer"]["contract_version"] == "1"
    assert event["mutation_authorized"] is False
    assert event["publication_dependency"] == {
        "tracker_required": False,
        "google_drive_required": False,
        "onedrive_required": False,
        "downstream_repo_required": False,
    }


def test_n1_tracker_absent_export_succeeds():
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "event.json"
        # No tracker path exists in this temp tree.
        assert not (Path(tmp) / "tracker.xlsx").exists()
        event = export_firmware_event({"identity": _unique_identity(), "target_logical_ref": "SYNTH-READER-A"})
        write_event(event, out)
        assert out.is_file()
        assert event["proof_ceiling"] == "UNIQUE_TARGET_RESOLVED"


def test_n2_n3_no_drive_onedrive_imports_or_paths():
    source = MODULE.read_text(encoding="utf-8")
    tree = ast.parse(source)
    imported = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.extend(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.append(node.module)
    forbidden = {"googleapiclient", "google.auth", "msal", "onedrivesdk", "openpyxl", "gspread"}
    assert forbidden.isdisjoint(set(imported))
    assert "drive.google.com" not in source.lower()
    assert "onedrive" not in source.lower() or "onedrive_required" in source
    event = export_firmware_event({"identity": _unique_identity()})
    assert event["publication_dependency"]["google_drive_required"] is False
    assert event["publication_dependency"]["onedrive_required"] is False


def test_n4_identical_evidence_same_event_id():
    identity = _unique_identity()
    baseline = _locked_baseline(identity)
    bundle = {
        "execution_run_id": "SYNTH-RUN-A",
        "target_logical_ref": "SYNTH-READER-A",
        "identity": identity,
        "baseline": baseline,
    }
    first = export_firmware_event(bundle)
    second = export_firmware_event(deepcopy(bundle))
    assert first["event_id"] == second["event_id"]
    assert first["evidence_fingerprint"] == second["evidence_fingerprint"]


def test_n5_changed_receipt_changes_event_id():
    identity = _unique_identity()
    baseline = _locked_baseline(identity)
    bundle_a = {
        "execution_run_id": "SYNTH-RUN-A",
        "target_logical_ref": "SYNTH-READER-A",
        "identity": identity,
        "baseline": baseline,
    }
    bundle_b = deepcopy(bundle_a)
    bundle_b["baseline"] = dict(baseline)
    bundle_b["baseline"]["current_firmware_value"] = "2.0.15.260411"
    a = export_firmware_event(bundle_a)
    b = export_firmware_event(bundle_b)
    assert a["event_id"] != b["event_id"]
    assert a["evidence_fingerprint"] != b["evidence_fingerprint"]


def test_n6_publication_fields_rejected_and_cannot_rewrite_truth():
    identity = _unique_identity()
    baseline = _locked_baseline(identity)
    good = export_firmware_event({"identity": identity, "baseline": baseline})
    try:
        export_firmware_event(
            {
                "identity": identity,
                "baseline": baseline,
                "publication_state": "FAILED_RETRYABLE",
            }
        )
        raise AssertionError("expected publication field rejection")
    except ValueError as exc:
        assert "publication_or_tracker_field_rejected" in str(exc)
    # Injecting publication metadata into a copy of the event object must not be
    # re-accepted as producer input that rewrites execution fields.
    mutated = dict(good)
    mutated["publication_state"] = "PUBLISHED"
    mutated["proof_ceiling"] = "FINAL_TARGET_RUNTIME_VERIFIED"
    # Producer ignores consumer-side mutation: re-export from receipts preserves ceiling.
    again = export_firmware_event({"identity": identity, "baseline": baseline})
    assert again["proof_ceiling"] == good["proof_ceiling"]
    assert again["observed_starting_firmware"] == good["observed_starting_firmware"]
    assert again["event_id"] == good["event_id"]


def test_n7_incomplete_evidence_does_not_invent_firmware():
    identity = _unique_identity()
    incomplete = freeze_baseline(
        {
            "source_serial": identity["source_serial"],
            "source_name": identity["source_name"],
            "expected_mac": identity["expected_mac"],
            "live_mac": identity["live_mac"],
            "live_ipv4": identity["live_ipv4"],
            "probe_mac_match": True,
            "identity_proof_state": "UNIQUE_TARGET_RESOLVED",
            "target_firmware_value": "2.0.15.260522",
        },
        identity,
    )
    assert incomplete["baseline_locked"] is False
    event = export_firmware_event(
        {
            "identity": identity,
            "baseline": incomplete,
            "governed_target_firmware": "2.0.15.260522",
            "target_logical_ref": "SYNTH-READER-A",
        }
    )
    assert event["observed_starting_firmware"] is None
    assert event["proof_ceiling"] == "BASELINE_INCOMPLETE"
    assert event["execution_disposition"] == "BLOCKED"
    assert event["canonical_execution_state"] == "BASELINE_INCOMPLETE"


def test_n8_tracked_fixtures_have_no_live_kiosk4_identifiers():
    for path in (GOLDEN, BLOCKED_FIXTURE, BUNDLE_GOLDEN, MODULE, SCHEMA_PATH):
        text = path.read_text(encoding="utf-8")
        for token in LIVE_FORBIDDEN:
            assert token not in text, f"{path} contains forbidden live token {token}"
    for path in (GOLDEN, BLOCKED_FIXTURE, BUNDLE_GOLDEN):
        assert "Kiosk4" not in path.read_text(encoding="utf-8")


def test_positive_identity_and_baseline_and_roundtrip_and_final():
    identity = _unique_identity()
    identity_event = export_firmware_event({"identity": identity, "target_logical_ref": "SYNTH-READER-A"})
    assert identity_event["proof_ceiling"] == "UNIQUE_TARGET_RESOLVED"

    baseline = _locked_baseline(identity)
    baseline_event = export_firmware_event(
        {"identity": identity, "baseline": baseline, "target_logical_ref": "SYNTH-READER-A"}
    )
    assert baseline_event["proof_ceiling"] == "BASELINE_LOCKED"
    assert baseline_event["observed_starting_firmware"] == "2.0.15.260410"

    eligibility = evaluate_outdated_eligibility(
        observed_firmware="2.0.15.260410",
        active_outdated="Yes",
        target_firmware="2.0.15.260522",
        source_serial=identity["source_serial"],
        expected_mac=identity["expected_mac"],
    )
    restore = evaluate_restore_path(
        {
            "source_serial": identity["source_serial"],
            "expected_mac": identity["expected_mac"],
            "starting_firmware_value": "2.0.15.260410",
            "restore_mechanism": "management-plane-reassign",
            "restore_package_or_release_ref": "SYNTH-PKG-260410",
            "rollback_verb": "reassign",
            "post_restore_acceptance": "authoritative-firmware-match",
        },
        baseline,
    )
    assert restore["restore_path_proved"] is True

    post_update = {
        "source_serial": identity["source_serial"],
        "expected_mac": identity["expected_mac"],
        "reader_ipv4": identity["live_ipv4"],
        "current_firmware_value": "2.0.15.260522",
        "state": "TARGET_UPDATE_PROVED",
        "forward_update_proved": True,
        "optional_captured": {"health_status": "online", "reader_ipv4": identity["live_ipv4"]},
    }
    post_rollback = {
        "source_serial": identity["source_serial"],
        "expected_mac": identity["expected_mac"],
        "reader_ipv4": identity["live_ipv4"],
        "current_firmware_value": "2.0.15.260410",
        "state": "ORIGINAL_STATE_RESTORED",
        "original_state_restored": True,
        "optional_captured": {"health_status": "online", "reader_ipv4": identity["live_ipv4"]},
    }
    compare = compare_roundtrip_states(baseline, post_update, post_rollback)
    assert compare.get("roundtrip_proven") is True or compare.get("state") == "ROUNDTRIP_PROVEN"

    forward_event = export_firmware_event(
        {
            "identity": identity,
            "baseline": baseline,
            "eligibility": eligibility,
            "restore_path": restore,
            "post_update": post_update,
            "target_logical_ref": "SYNTH-READER-A",
        }
    )
    assert forward_event["proof_ceiling"] == "TARGET_UPDATE_PROVED"

    roundtrip_event = export_firmware_event(
        {
            "identity": identity,
            "baseline": baseline,
            "eligibility": eligibility,
            "restore_path": restore,
            "compare": compare,
            "post_update": post_update,
            "post_rollback": post_rollback,
            "target_logical_ref": "SYNTH-READER-A",
        }
    )
    assert roundtrip_event["proof_ceiling"] in {
        "ROUNDTRIP_PROVEN",
        "SINGLE_READER_ROUNDTRIP_PROVED",
    }

    final_runtime = {
        "artifact": "final-runtime-verification",
        "state": "FINAL_TARGET_RUNTIME_VERIFIED",
        "final_runtime_verified": True,
        "source_serial": identity["source_serial"],
        "expected_mac": identity["expected_mac"],
        "current_firmware_value": "2.0.15.260522",
    }
    final_event = export_firmware_event(
        {
            "identity": identity,
            "baseline": baseline,
            "eligibility": eligibility,
            "restore_path": restore,
            "compare": compare,
            "post_update": post_update,
            "post_rollback": post_rollback,
            "final_runtime": final_runtime,
            "target_logical_ref": "SYNTH-READER-A",
            "execution_run_id": "SYNTH-RUN-FINAL",
        }
    )
    assert final_event["proof_ceiling"] == "FINAL_TARGET_RUNTIME_VERIFIED"
    assert final_event["observed_resulting_firmware"] == "2.0.15.260522"


def test_proof_ceiling_not_strengthened_by_event_class_claim():
    identity = _unique_identity()
    try:
        export_firmware_event(
            {
                "identity": identity,
                "event_class": "FINAL_TARGET_RUNTIME_VERIFIED",
            }
        )
        raise AssertionError("expected event_class overclaim rejection")
    except ValueError as exc:
        assert "event_class_exceeds_proof_ceiling" in str(exc)


def test_golden_fixture_matches_exporter_from_bundle():
    bundle = json.loads(BUNDLE_GOLDEN.read_text(encoding="utf-8"))
    event = export_firmware_event(bundle)
    golden = json.loads(GOLDEN.read_text(encoding="utf-8"))
    assert event["event_id"] == golden["event_id"]
    assert event["evidence_fingerprint"] == golden["evidence_fingerprint"]
    assert event["proof_ceiling"] == "FINAL_TARGET_RUNTIME_VERIFIED"
    assert golden["schema"] == SCHEMA


def test_cli_export_offline():
    with tempfile.TemporaryDirectory() as tmp:
        bundle_path = Path(tmp) / "bundle.json"
        out_path = Path(tmp) / "event.json"
        bundle_path.write_text(
            json.dumps(
                {
                    "identity": _unique_identity(),
                    "target_logical_ref": "SYNTH-READER-A",
                    "execution_run_id": "SYNTH-CLI-1",
                }
            ),
            encoding="utf-8",
        )
        completed = subprocess.run(
            [
                sys.executable,
                str(MODULE),
                "--input",
                str(bundle_path),
                "--output",
                str(out_path),
            ],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            check=False,
        )
        assert completed.returncode == 0, completed.stderr
        assert out_path.is_file()
        event = json.loads(out_path.read_text(encoding="utf-8"))
        assert event["schema"] == SCHEMA
        assert "EVENT_ID=" in completed.stdout


def test_fingerprint_helper_deterministic():
    payload = {"a": 1, "b": [2, 3]}
    assert fingerprint_payload(payload) == fingerprint_payload({"b": [2, 3], "a": 1})


def test_roundtrip_module_still_importable():
    assert ROUNDTRIP_MODULE.is_file()


def main() -> int:
    tests = [
        test_tracked_surfaces_exist,
        test_schema_const_and_producer_metadata,
        test_n1_tracker_absent_export_succeeds,
        test_n2_n3_no_drive_onedrive_imports_or_paths,
        test_n4_identical_evidence_same_event_id,
        test_n5_changed_receipt_changes_event_id,
        test_n6_publication_fields_rejected_and_cannot_rewrite_truth,
        test_n7_incomplete_evidence_does_not_invent_firmware,
        test_n8_tracked_fixtures_have_no_live_kiosk4_identifiers,
        test_positive_identity_and_baseline_and_roundtrip_and_final,
        test_proof_ceiling_not_strengthened_by_event_class_claim,
        test_golden_fixture_matches_exporter_from_bundle,
        test_cli_export_offline,
        test_fingerprint_helper_deterministic,
        test_roundtrip_module_still_importable,
    ]
    failed = 0
    for test in tests:
        try:
            test()
            print(f"PASS {test.__name__}")
        except Exception as exc:  # noqa: BLE001 - contract runner
            failed += 1
            print(f"FAIL {test.__name__}: {exc}")
    if failed:
        print(f"FAILED {failed}/{len(tests)}")
        return 1
    print(f"PASSED {len(tests)}/{len(tests)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
