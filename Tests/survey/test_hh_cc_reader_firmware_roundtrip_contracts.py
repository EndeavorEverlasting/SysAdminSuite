#!/usr/bin/env python3
"""Fail-closed contracts for H&H CC-reader firmware round-trip / batch seams."""
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_firmware_roundtrip import (
    compare_roundtrip_states,
    evaluate_mutation_admission,
    evaluate_outdated_eligibility,
    evaluate_restore_path,
    freeze_baseline,
    load_batch_csv,
    normalize_batch_rows,
    resolve_target_identity,
)
from harness.api.hh_cc_reader_estate_packet_normalize import load_packet_or_template, normalize_packet
from harness.api.hh_cc_reader_estate_authority import evaluate

MODULE = ROOT / "harness/api/hh_cc_reader_firmware_roundtrip.py"
EVAL_CMD = ROOT / "Evaluate-HHCCReaderFirmwareRoundtrip.cmd"
BATCH_CMD = ROOT / "Normalize-HHCCReaderFirmwareBatch.cmd"
EXAMPLE_CSV = ROOT / "docs/examples/hh-cc-reader-firmware-batch.example.csv"
EVIDENCE_MAP = ROOT / "docs/HH_CC_READER_KIOSK4_ROUNDTRIP_EVIDENCE_MAP.md"
TEMPLATE = ROOT / "docs/examples/hh-cc-reader-proven-path-authority-packet.template.json"


def _unique_identity(**overrides):
    base = {
        "source_serial": "SYNTH-SERIAL-001",
        "source_name": "SyntheticLabReader",
        "expected_mac": "AA-BB-CC-DD-EE-01",
        "live_mac": "AA:BB:CC:DD:EE:01",
        "live_ipv4": "192.0.2.10",
        "probe_mac_match": True,
    }
    base.update(overrides)
    return base


def test_module_launchers_and_example_exist() -> None:
    assert MODULE.is_file()
    assert EVAL_CMD.is_file()
    assert BATCH_CMD.is_file()
    assert EXAMPLE_CSV.is_file()
    assert EVIDENCE_MAP.is_file()
    text = EVAL_CMD.read_text(encoding="utf-8-sig")
    assert "hh_cc_reader_firmware_roundtrip.py" in text
    assert "Never authorizes" in text or "never authorizes" in text.lower()


def test_ambiguous_and_readerunk_identity_fail_closed() -> None:
    incomplete = resolve_target_identity(
        {
            "source_serial": "SYNTH-SERIAL-001",
            "expected_mac": "AA-BB-CC-DD-EE-01",
        }
    )
    assert incomplete["unique_target"] is False
    assert incomplete["state"] == "IDENTITY_INCOMPLETE"
    assert incomplete["mutation_authorized"] is False

    mismatch = resolve_target_identity(
        _unique_identity(live_mac="AA-BB-CC-DD-EE-99", probe_mac_match=False)
    )
    assert mismatch["unique_target"] is False
    assert "live_mac_mismatch" in mismatch["rejection_reasons"]

    # Construct forbidden specimen without embedding production literals as Kiosk4 truth.
    readerunk = resolve_target_identity(
        _unique_identity(
            live_ipv4=".".join(["10", "217", "101", "192"]),
            expected_mac="C8-40-52-3C-54-B6",
            live_mac="C8:40:52:3C:54:B6",
        )
    )
    assert readerunk["state"] == "DEVICE_MISMATCH"
    assert readerunk["unique_target"] is False

    unique = resolve_target_identity(_unique_identity())
    assert unique["state"] == "UNIQUE_TARGET_RESOLVED"
    assert unique["unique_target"] is True


def test_missing_baseline_blocks_mutation_preview() -> None:
    identity = resolve_target_identity(_unique_identity())
    incomplete = freeze_baseline(
        {
            "source_serial": identity["source_serial"],
            "expected_mac": identity["expected_mac"],
            # missing firmware / identity_proof_state
        },
        identity,
    )
    assert incomplete["baseline_locked"] is False
    assert incomplete["state"] == "BASELINE_INCOMPLETE"

    baseline_obs = {
        **_unique_identity(),
        "identity_proof_state": "UNIQUE_TARGET_RESOLVED",
        "current_firmware_value": "2.0.15.260410",
        "target_firmware_value": "2.0.15.260522",
        "health_status": "online",
    }
    baseline = freeze_baseline(baseline_obs, identity)
    assert baseline["baseline_locked"] is True

    restore = evaluate_restore_path(
        {
            "starting_firmware_value": "2.0.15.260410",
            "restore_mechanism": "management-plane reassignment observed",
            "restore_package_or_release_ref": "starting-package-ref-synthetic",
            "rollback_verb": "reassign",
            "post_restore_acceptance": "authoritative firmware equals baseline",
        },
        baseline,
    )
    assert restore["restore_path_proved"] is True

    eligibility = evaluate_outdated_eligibility(
        observed_firmware="2.0.15.260410",
        active_outdated="Yes",
        target_firmware="2.0.15.260522",
    )
    assert eligibility["outdated_classified"] is True

    blocked = evaluate_mutation_admission(
        identity=identity,
        baseline=incomplete,
        restore_path=restore,
        eligibility=eligibility,
        authority_packet_state="COMPLETE",
        explicit_one_reader_mutation_authorization=True,
        dry_run=True,
    )
    assert blocked["state"] == "MUTATION_BLOCKED"
    assert "baseline_not_locked" in blocked["blockers"]
    assert blocked["mutation_authorized"] is False

    preview = evaluate_mutation_admission(
        identity=identity,
        baseline=baseline,
        restore_path=restore,
        eligibility=eligibility,
        authority_packet_state="COMPLETE",
        explicit_one_reader_mutation_authorization=True,
        dry_run=True,
    )
    assert preview["state"] == "MUTATION_PREVIEW_READY"
    assert preview["mutation_authorized"] is False
    assert preview["dry_run_plan"]["source_firmware"] == "2.0.15.260410"
    assert preview["dry_run_plan"]["target_firmware"] == "2.0.15.260522"


def test_eligibility_does_not_invent_outdated_from_version_order_alone() -> None:
    result = evaluate_outdated_eligibility(
        observed_firmware="2.0.14.221110",
        active_outdated="No",
        target_firmware="2.0.15.260522",
    )
    assert result["outdated_classified"] is False
    assert result["state"] == "RECONCILIATION_REQUIRED"

    current = evaluate_outdated_eligibility(
        observed_firmware="2.0.15.260522",
        active_outdated="Yes",
        target_firmware="2.0.15.260522",
    )
    assert current["state"] == "RECONCILIATION_REQUIRED"
    assert current["outdated_classified"] is False


def test_rollback_compare_detects_drift_and_accepts_restore() -> None:
    baseline = {
        "current_firmware_value": "2.0.15.260410",
        "source_serial": "SYNTH-SERIAL-001",
        "expected_mac": "AABBCCDDEE01",
        "optional_captured": {
            "health_status": "online",
            "configuration_profile_ref": "profile-a",
        },
    }
    post_update = {
        "current_firmware_value": "2.0.15.260522",
        "source_serial": "SYNTH-SERIAL-001",
        "expected_mac": "AABBCCDDEE01",
        "optional_captured": {
            "health_status": "online",
            "configuration_profile_ref": "profile-a",
        },
    }
    good_rollback = {
        "current_firmware_value": "2.0.15.260410",
        "source_serial": "SYNTH-SERIAL-001",
        "expected_mac": "AABBCCDDEE01",
        "optional_captured": {
            "health_status": "online",
            "configuration_profile_ref": "profile-a",
        },
    }
    drifted = {
        "current_firmware_value": "2.0.15.260522",
        "source_serial": "SYNTH-SERIAL-001",
        "expected_mac": "AABBCCDDEE01",
        "optional_captured": {
            "health_status": "degraded",
            "configuration_profile_ref": "profile-b",
        },
    }
    ok = compare_roundtrip_states(baseline, post_update, good_rollback)
    assert ok["state"] == "ORIGINAL_STATE_RESTORED"
    assert ok["restored"] is True

    bad = compare_roundtrip_states(baseline, post_update, drifted)
    assert bad["state"] == "ROLLBACK_DRIFT_DETECTED"
    assert "current_firmware_value" in bad["mismatched_fields"]
    assert "health_status" in bad["mismatched_fields"]
    assert "configuration_profile_ref" in bad["mismatched_fields"]


def test_batch_normalize_fail_closed_and_single_device_scope() -> None:
    rows = [
        {
            "source_serial": "SYNTH-001",
            "source_name": "ReaderA",
            "expected_mac": "AA-BB-CC-DD-EE-01",
            "observed_firmware": "2.0.15.260410",
            "active_outdated": "Yes",
            "target_firmware": "2.0.15.260522",
            "action": "PLAN",
        },
        {
            "source_serial": "SYNTH-002",
            "source_name": "ReaderB",
            "expected_mac": "AA-BB-CC-DD-EE-02",
            "observed_firmware": "2.0.15.260410",
            "active_outdated": "Yes",
            "target_firmware": "2.0.15.260522",
            "action": "PLAN",
        },
        {
            "source_serial": "SYNTH-001",
            "source_name": "Dup",
            "expected_mac": "AA-BB-CC-DD-EE-03",
            "observed_firmware": "2.0.15.260410",
            "active_outdated": "Yes",
            "target_firmware": "2.0.15.260522",
            "action": "UPDATE",
        },
        {
            "source_serial": "SYNTH-003",
            "source_name": "BadMac",
            "expected_mac": "not-a-mac",
            "observed_firmware": "2.0.15.260410",
            "active_outdated": "Yes",
            "target_firmware": "2.0.15.260522",
            "action": "PLAN",
        },
    ]
    plan = normalize_batch_rows(rows)
    assert plan["mutation_authorized"] is False
    assert plan["blocked_count"] >= 2
    assert any("duplicate_source_serial" in row["problems"] for row in plan["blocked_rows"])
    assert any("invalid_expected_mac" in row["problems"] for row in plan["blocked_rows"])

    scoped = normalize_batch_rows(rows[:2], execute_serial="SYNTH-001")
    assert scoped["executable_count"] == 1
    assert scoped["executable_rows"][0]["source_serial"] == "SYNTH-001"
    assert any("outside_single_device_execution_scope" in row["problems"] for row in scoped["blocked_rows"])

    example_rows = load_batch_csv(EXAMPLE_CSV)
    example_plan = normalize_batch_rows(example_rows)
    # Placeholder REPLACE-WITH rows are present and parseable; they remain non-live.
    assert example_plan["row_count"] == 2
    assert all(row["source_serial"].startswith("REPLACE-WITH") for row in example_plan["rows"])


def test_p5_normalize_evaluate_not_weakened() -> None:
    normalized = normalize_packet(load_packet_or_template(TEMPLATE))
    result = evaluate(normalized["evaluator_inputs"])
    assert result["packet_state"] == "BLOCKED_AUTHORITY"
    assert result["next_gate"] == "AUTHORIZED_READONLY_SESSION"
    assert result["mutation_authorized"] is False


def test_cli_identity_and_compare_modes() -> None:
    import subprocess

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        identity_in = tmp_path / "identity.json"
        identity_out = tmp_path / "identity-out.json"
        identity_in.write_text(json.dumps(_unique_identity()), encoding="utf-8")
        completed = subprocess.run(
            [
                sys.executable,
                str(MODULE),
                "identity",
                "--input",
                str(identity_in),
                "--output",
                str(identity_out),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        assert completed.returncode == 0
        payload = json.loads(identity_out.read_text(encoding="utf-8"))
        assert payload["state"] == "UNIQUE_TARGET_RESOLVED"

        compare_in = tmp_path / "compare.json"
        compare_out = tmp_path / "compare-out.json"
        compare_in.write_text(
            json.dumps(
                {
                    "baseline": {"current_firmware_value": "A", "source_serial": "S1"},
                    "post_update": {"current_firmware_value": "B", "source_serial": "S1"},
                    "post_rollback": {"current_firmware_value": "A", "source_serial": "S1"},
                }
            ),
            encoding="utf-8",
        )
        subprocess.run(
            [
                sys.executable,
                str(MODULE),
                "compare",
                "--input",
                str(compare_in),
                "--output",
                str(compare_out),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        compare_payload = json.loads(compare_out.read_text(encoding="utf-8"))
        assert compare_payload["state"] == "ORIGINAL_STATE_RESTORED"


if __name__ == "__main__":
    tests = [
        test_module_launchers_and_example_exist,
        test_ambiguous_and_readerunk_identity_fail_closed,
        test_missing_baseline_blocks_mutation_preview,
        test_eligibility_does_not_invent_outdated_from_version_order_alone,
        test_rollback_compare_detects_drift_and_accepts_restore,
        test_batch_normalize_fail_closed_and_single_device_scope,
        test_p5_normalize_evaluate_not_weakened,
        test_cli_identity_and_compare_modes,
    ]
    failures = 0
    for test in tests:
        try:
            test()
            print(f"PASS {test.__name__}")
        except Exception as exc:  # noqa: BLE001 - surface exact contract failure
            failures += 1
            print(f"FAIL {test.__name__}: {exc}")
    raise SystemExit(1 if failures else 0)
