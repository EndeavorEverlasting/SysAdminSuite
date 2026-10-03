#!/usr/bin/env python3
"""Fail-closed contracts for H&H CC-reader firmware round-trip / batch seams."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_firmware_roundtrip import (
    classify_identity_tranche,
    compare_roundtrip_states,
    default_target_firmware,
    evaluate_mutation_admission,
    evaluate_outdated_eligibility,
    evaluate_restore_path,
    freeze_baseline,
    load_batch_input,
    load_policy,
    normalize_batch_rows,
    resolve_target_identity,
    write_receipt,
)
from harness.api.hh_cc_reader_estate_packet_normalize import load_packet_or_template, normalize_packet
from harness.api.hh_cc_reader_estate_authority import evaluate

MODULE = ROOT / "harness/api/hh_cc_reader_firmware_roundtrip.py"
EVAL_CMD = ROOT / "Evaluate-HHCCReaderFirmwareRoundtrip.cmd"
BATCH_CMD = ROOT / "Normalize-HHCCReaderFirmwareBatch.cmd"
EXAMPLE_CSV = ROOT / "docs/examples/hh-cc-reader-firmware-batch.example.csv"
EVIDENCE_MAP = ROOT / "docs/HH_CC_READER_KIOSK4_ROUNDTRIP_EVIDENCE_MAP.md"
ROUNDTRIP_PLAN = ROOT / "docs/HH_CC_READER_FIRMWARE_ROUNDTRIP_BATCH_PLAN.md"
TEMPLATE = ROOT / "docs/examples/hh-cc-reader-proven-path-authority-packet.template.json"

PROHIBITED_LIVE_MARKERS = (
    "1240473751",
    "C8:40:52:3C:93:BA",
    "C8-40-52-3C-93-BA",
    "C840523C93BA",
)


def _unique_identity(**overrides):
    base = {
        "source_serial": "SYNTH-SERIAL-001",
        "source_name": "SyntheticLabReader",
        "expected_mac": "AA-BB-CC-DD-EE-01",
        "live_mac": "AA:BB:CC:DD:EE:01",
        "live_ipv4": "192.0.2.10",
        "probe_mac_match": True,
        "network_environment": "CONSUMER_LAB",
    }
    base.update(overrides)
    return base


def _device_b(**overrides):
    base = _unique_identity(
        source_serial="SYNTH-SERIAL-002",
        source_name="SyntheticLabReaderB",
        expected_mac="AA-BB-CC-DD-EE-02",
        live_mac="AA:BB:CC:DD:EE:02",
        live_ipv4="192.0.2.11",
    )
    base.update(overrides)
    return base


def _locked_bundle(identity_src=None):
    identity_src = identity_src or _unique_identity()
    identity = resolve_target_identity(identity_src)
    observation = {
        **identity_src,
        "identity_proof_state": "UNIQUE_TARGET_RESOLVED",
        "current_firmware_value": "2.0.15.260410",
        "target_firmware_value": "2.0.15.260522",
        "health_status": "online",
        "configuration_profile_ref": "profile-a",
    }
    baseline = freeze_baseline(observation, identity)
    restore = evaluate_restore_path(
        {
            "source_serial": identity["source_serial"],
            "expected_mac": identity["expected_mac"],
            "starting_firmware_value": "2.0.15.260410",
            "restore_mechanism": "management-plane reassignment observed",
            "restore_package_or_release_ref": "starting-package-ref-synthetic",
            "rollback_verb": "reassign",
            "post_restore_acceptance": "authoritative firmware equals baseline",
        },
        baseline,
    )
    eligibility = evaluate_outdated_eligibility(
        observed_firmware="2.0.15.260410",
        active_outdated="Yes",
        target_firmware="2.0.15.260522",
        source_serial=identity["source_serial"],
        expected_mac=identity["expected_mac"],
    )
    return identity, baseline, restore, eligibility


def test_module_launchers_and_example_exist() -> None:
    assert MODULE.is_file()
    assert EVAL_CMD.is_file()
    assert BATCH_CMD.is_file()
    assert EXAMPLE_CSV.is_file()
    assert EVIDENCE_MAP.is_file()
    text = EVAL_CMD.read_text(encoding="utf-8-sig")
    assert "hh_cc_reader_firmware_roundtrip.py" in text
    assert "survey" in text.lower()


def test_tracked_docs_have_no_prohibited_live_identifiers() -> None:
    for path in (EVIDENCE_MAP, ROUNDTRIP_PLAN):
        text = path.read_text(encoding="utf-8")
        for marker in PROHIBITED_LIVE_MARKERS:
            assert marker not in text, f"{path.name} still contains {marker}"
        assert "PRIVATE_EVIDENCE" in text or "PRIVATE_FIELD" in text


def test_ambiguous_and_readerunk_identity_fail_closed() -> None:
    incomplete = resolve_target_identity(
        {"source_serial": "SYNTH-SERIAL-001", "expected_mac": "AA-BB-CC-DD-EE-01"}
    )
    assert incomplete["unique_target"] is False
    assert incomplete["state"] == "IDENTITY_INCOMPLETE"

    mismatch = resolve_target_identity(
        _unique_identity(live_mac="AA-BB-CC-DD-EE-99", probe_mac_match=False)
    )
    assert mismatch["unique_target"] is False
    assert "live_mac_mismatch" in mismatch["rejection_reasons"]

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


def test_identity_tranches_preserve_strict_mutation_gate() -> None:
    dual = classify_identity_tranche(
        {"source_serial": "SYNTH-TR-001", "expected_mac": "AA-BB-CC-DD-EE-11"}
    )
    assert dual["tranche"] == "SERIAL_AND_MAC"
    assert dual["inventory_inputs_complete"] is True
    assert dual["next_gate"] == "MAC_GATED_ONE_TARGET_PROBE"
    assert dual["broad_discovery_authorized"] is False
    assert dual["mutation_authorized"] is False

    serial_only = classify_identity_tranche({"source_serial": "SYNTH-TR-002"})
    assert serial_only["tranche"] == "SERIAL_ONLY"
    assert "RECOVER_MAC" in serial_only["next_gate"]

    mac_only = classify_identity_tranche({"expected_mac": "AA-BB-CC-DD-EE-13"})
    assert mac_only["tranche"] == "MAC_ONLY"
    assert "RECOVER_SERIAL" in mac_only["next_gate"]

    insufficient = classify_identity_tranche({})
    assert insufficient["tranche"] == "IDENTITY_INSUFFICIENT"
    assert insufficient["next_gate"] == "RECONCILE_READER_IDENTITY_BEFORE_NETWORK_PROBE"

    malformed = classify_identity_tranche(
        {"source_serial": "SYNTH-TR-004", "expected_mac": "not-a-mac"}
    )
    assert malformed["tranche"] == "IDENTITY_INVALID"
    assert malformed["next_gate"] == "CORRECT_MALFORMED_MAC"

    serial_resolve = resolve_target_identity(
        {
            "source_serial": "SYNTH-TR-002",
            "live_ipv4": "192.0.2.20",
            "probe_mac_match": False,
        }
    )
    assert serial_resolve["state"] == "IDENTITY_INCOMPLETE"
    assert serial_resolve["identity_tranche"] == "SERIAL_ONLY"
    assert serial_resolve["unique_target"] is False
    assert serial_resolve["broad_discovery_authorized"] is False

    mac_resolve = resolve_target_identity(
        {
            "expected_mac": "AA-BB-CC-DD-EE-13",
            "live_mac": "AA:BB:CC:DD:EE:13",
            "live_ipv4": "192.0.2.21",
            "probe_mac_match": True,
        }
    )
    assert mac_resolve["state"] == "IDENTITY_INCOMPLETE"
    assert mac_resolve["identity_tranche"] == "MAC_ONLY"
    assert mac_resolve["unique_target"] is False

    unclassified_network = resolve_target_identity(
        _unique_identity(network_environment=None)
    )
    assert unclassified_network["state"] == "IDENTITY_INCOMPLETE"
    assert "network_environment_unclassified" in unclassified_network["rejection_reasons"]
    assert unclassified_network["network_environment_classified"] is False

    invalid_network = resolve_target_identity(
        _unique_identity(network_environment="HOMEISH")
    )
    assert invalid_network["state"] == "IDENTITY_INCOMPLETE"
    assert "network_environment_invalid" in invalid_network["rejection_reasons"]

    guest_network = resolve_target_identity(
        _unique_identity(network_environment="HOSPITAL_GUEST_SHARED")
    )
    assert guest_network["state"] == "UNIQUE_TARGET_RESOLVED"
    assert guest_network["network_environment"] == "HOSPITAL_GUEST_SHARED"
    assert guest_network["network_environment_classified"] is True

    common = {
        "source_name": "SyntheticReader",
        "observed_firmware": "2.0.15.260410",
        "active_outdated": "Yes",
        "target_firmware": "2.0.15.260522",
        "action": "PLAN",
    }
    plan = normalize_batch_rows(
        [
            {**common, "source_serial": "SYNTH-TR-101", "expected_mac": "AA-BB-CC-DD-EE-21"},
            {**common, "source_serial": "SYNTH-TR-102", "expected_mac": ""},
            {**common, "source_serial": "", "expected_mac": "AA-BB-CC-DD-EE-23"},
            {**common, "source_serial": "", "expected_mac": ""},
        ]
    )
    assert plan["identity_tranche_counts"] == {
        "SERIAL_AND_MAC": 1,
        "SERIAL_ONLY": 1,
        "MAC_ONLY": 1,
        "IDENTITY_INSUFFICIENT": 1,
    }
    assert plan["identity_recovery_count"] == 3
    assert len(plan["identity_recovery_rows"]) == 3
    assert plan["executable_count"] == 1
    assert all(not row["broad_discovery_authorized"] for row in plan["rows"])


def test_strict_mac_validation_rejects_garbage_hex_extraction() -> None:
    garbage = resolve_target_identity(
        _unique_identity(expected_mac="xxAABBCCDDEE01yy", live_mac="xxAABBCCDDEE01yy")
    )
    assert garbage["unique_target"] is False
    assert "malformed_expected_mac" in garbage["rejection_reasons"]

    spaced = resolve_target_identity(
        _unique_identity(expected_mac="AA BB CC DD EE 01", live_mac="AA BB CC DD EE 01")
    )
    assert spaced["unique_target"] is False

    for good in ("AA:BB:CC:DD:EE:01", "AA-BB-CC-DD-EE-01", "AABBCCDDEE01"):
        result = resolve_target_identity(_unique_identity(expected_mac=good, live_mac=good))
        assert result["unique_target"] is True, good
        assert result["expected_mac"] == "AABBCCDDEE01"


def test_cross_device_receipt_binding_fail_closed() -> None:
    identity_a, baseline_a, restore_a, eligibility_a = _locked_bundle(_unique_identity())
    identity_b, baseline_b, restore_b, eligibility_b = _locked_bundle(_device_b())

    # identity(A) + baseline(B)
    cross_baseline = freeze_baseline(
        {
            **_device_b(),
            "identity_proof_state": "UNIQUE_TARGET_RESOLVED",
            "current_firmware_value": "2.0.15.260410",
            "target_firmware_value": "2.0.15.260522",
        },
        identity_a,
    )
    assert cross_baseline["baseline_locked"] is False
    assert "source_serial_identity_mismatch" in cross_baseline["missing_fields"]

    # identity(A) + restore(B) / baseline(A) + restore(B)
    cross_restore = evaluate_restore_path(
        {
            "source_serial": identity_b["source_serial"],
            "expected_mac": identity_b["expected_mac"],
            "starting_firmware_value": "2.0.15.260410",
            "restore_mechanism": "management-plane reassignment observed",
            "restore_package_or_release_ref": "starting-package-ref-synthetic",
            "rollback_verb": "reassign",
            "post_restore_acceptance": "authoritative firmware equals baseline",
        },
        baseline_a,
    )
    assert cross_restore["restore_path_proved"] is False
    assert any("mismatch" in item for item in cross_restore["missing_fields"])

    # eligibility(A) + identity(B) via preview
    preview = evaluate_mutation_admission(
        identity=identity_a,
        baseline=baseline_b,
        restore_path=restore_b,
        eligibility=eligibility_b,
        authority_packet_state="COMPLETE",
        explicit_one_reader_mutation_authorization=True,
        dry_run=False,
    )
    assert preview["state"] == "MUTATION_BLOCKED"
    assert preview["apply_candidate"] is False
    assert preview["mutation_authorized"] is False
    assert any("mismatch" in item for item in preview["blockers"])

    same = evaluate_mutation_admission(
        identity=identity_a,
        baseline=baseline_a,
        restore_path=restore_a,
        eligibility=eligibility_a,
        authority_packet_state="COMPLETE",
        explicit_one_reader_mutation_authorization=True,
        dry_run=True,
    )
    assert same["state"] == "MUTATION_PREVIEW_READY"
    assert same["mutation_authorized"] is False


def test_missing_baseline_blocks_mutation_and_compare() -> None:
    identity, baseline, restore, eligibility = _locked_bundle()
    incomplete = freeze_baseline(
        {"source_serial": identity["source_serial"], "expected_mac": identity["expected_mac"]},
        identity,
    )
    assert incomplete["baseline_locked"] is False

    blocked = evaluate_mutation_admission(
        identity=identity,
        baseline=incomplete,
        restore_path=restore,
        eligibility=eligibility,
        authority_packet_state="COMPLETE",
        explicit_one_reader_mutation_authorization=True,
    )
    assert blocked["state"] == "MUTATION_BLOCKED"
    assert "baseline_not_locked" in blocked["blockers"]

    empty_compare = compare_roundtrip_states({}, {"current_firmware_value": "X"}, {"current_firmware_value": "X"})
    assert empty_compare["state"] == "COMPARE_PREREQUISITES_MISSING"
    assert empty_compare["restored"] is False
    assert empty_compare["roundtrip_proven"] is False


def test_roundtrip_requires_forward_mutation_before_restore_proof() -> None:
    identity, baseline, restore, eligibility = _locked_bundle()
    assert baseline["baseline_locked"] is True

    post_update = {
        "source_serial": identity["source_serial"],
        "expected_mac": identity["expected_mac"],
        "reader_ipv4": identity["live_ipv4"],
        "current_firmware_value": "2.0.15.260522",
        "optional_captured": {
            "health_status": "online",
            "configuration_profile_ref": "profile-a",
        },
    }
    good_rollback = {
        "source_serial": identity["source_serial"],
        "expected_mac": identity["expected_mac"],
        "reader_ipv4": identity["live_ipv4"],
        "current_firmware_value": "2.0.15.260410",
        "optional_captured": {
            "health_status": "online",
            "configuration_profile_ref": "profile-a",
        },
    }
    no_mutation = {
        "source_serial": identity["source_serial"],
        "expected_mac": identity["expected_mac"],
        "reader_ipv4": identity["live_ipv4"],
        "current_firmware_value": "2.0.15.260410",
        "optional_captured": {
            "health_status": "online",
            "configuration_profile_ref": "profile-a",
        },
    }
    drifted = {
        "source_serial": identity["source_serial"],
        "expected_mac": identity["expected_mac"],
        "reader_ipv4": identity["live_ipv4"],
        "current_firmware_value": "2.0.15.260522",
        "optional_captured": {
            "health_status": "degraded",
            "configuration_profile_ref": "profile-b",
        },
    }

    ok = compare_roundtrip_states(baseline, post_update, good_rollback)
    assert ok["forward_update_proved"] is True
    assert ok["rollback_state_matched"] is True
    assert ok["roundtrip_proven"] is True
    assert ok["state"] == "ROUNDTRIP_PROVEN"

    unchanged = compare_roundtrip_states(baseline, no_mutation, no_mutation)
    assert unchanged["forward_update_proved"] is False
    assert unchanged["rollback_state_matched"] is True
    assert unchanged["roundtrip_proven"] is False
    assert unchanged["state"] == "ROLLBACK_STATE_MATCHED"

    bad = compare_roundtrip_states(baseline, post_update, drifted)
    assert bad["state"] == "ROLLBACK_DRIFT_DETECTED"
    assert "current_firmware_value" in bad["mismatched_fields"]


def test_policy_default_target_is_authoritative() -> None:
    from harness.api.hh_cc_reader_firmware_roundtrip import load_policy as lp

    policy = load_policy()
    assert default_target_firmware(policy) == policy["selection"]["default_target"]

    changed = deepcopy(policy)
    changed["selection"]["default_target"] = "9.9.9.999999"
    assert default_target_firmware(changed) == "9.9.9.999999"
    result = evaluate_outdated_eligibility(
        observed_firmware="2.0.15.260410",
        active_outdated="Yes",
        policy=changed,
        source_serial="SYNTH-SERIAL-001",
        expected_mac="AA-BB-CC-DD-EE-01",
    )
    assert result["target_firmware"] == "9.9.9.999999"
    assert result["outdated_classified"] is True

    with tempfile.TemporaryDirectory() as tmp:
        bad = Path(tmp) / "bad-policy.json"
        broken = deepcopy(policy)
        broken["schema_version"] = "not-a-real-schema"
        bad.write_text(json.dumps(broken), encoding="utf-8")
        try:
            lp(bad)
            raise AssertionError("expected schema ValueError")
        except ValueError as exc:
            assert "schema_version" in str(exc)

        missing = Path(tmp) / "missing-target.json"
        missing_target = deepcopy(policy)
        missing_target["selection"] = {"rule": "x"}
        missing.write_text(json.dumps(missing_target), encoding="utf-8")
        try:
            lp(missing)
            raise AssertionError("expected missing default_target ValueError")
        except ValueError as exc:
            assert "default_target" in str(exc)


def test_batch_duplicate_groups_block_all_members_and_scope() -> None:
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
            "source_serial": "SYNTH-001",
            "source_name": "DupSerial",
            "expected_mac": "AA-BB-CC-DD-EE-02",
            "observed_firmware": "2.0.15.260410",
            "active_outdated": "Yes",
            "target_firmware": "2.0.15.260522",
            "action": "PLAN",
        },
        {
            "source_serial": "SYNTH-003",
            "source_name": "DupMac1",
            "expected_mac": "AA-BB-CC-DD-EE-03",
            "observed_firmware": "2.0.15.260410",
            "active_outdated": "Yes",
            "target_firmware": "2.0.15.260522",
            "action": "PLAN",
        },
        {
            "source_serial": "SYNTH-004",
            "source_name": "DupMac2",
            "expected_mac": "AA-BB-CC-DD-EE-03",
            "observed_firmware": "2.0.15.260410",
            "active_outdated": "Yes",
            "target_firmware": "2.0.15.260522",
            "action": "PLAN",
        },
        {
            "source_serial": "SYNTH-005",
            "source_name": "Trip1",
            "expected_mac": "AA-BB-CC-DD-EE-05",
            "observed_firmware": "2.0.15.260410",
            "active_outdated": "Yes",
            "target_firmware": "2.0.15.260522",
            "action": "PLAN",
        },
        {
            "source_serial": "SYNTH-005",
            "source_name": "Trip2",
            "expected_mac": "AA-BB-CC-DD-EE-05",
            "observed_firmware": "2.0.15.260410",
            "active_outdated": "Yes",
            "target_firmware": "2.0.15.260522",
            "action": "PLAN",
        },
        {
            "source_serial": "SYNTH-005",
            "source_name": "Trip3",
            "expected_mac": "AA-BB-CC-DD-EE-05",
            "observed_firmware": "2.0.15.260410",
            "active_outdated": "Yes",
            "target_firmware": "2.0.15.260522",
            "action": "PLAN",
        },
    ]
    plan = normalize_batch_rows(rows)
    assert plan["executable_count"] == 0
    assert all(not row["executable"] for row in plan["rows"])
    assert "duplicate_source_serial" in plan["rows"][0]["problems"]
    assert "duplicate_source_serial" in plan["rows"][1]["problems"]
    assert "duplicate_expected_mac" in plan["rows"][2]["problems"]
    assert "duplicate_expected_mac" in plan["rows"][3]["problems"]

    scoped = normalize_batch_rows(rows, execute_serial="SYNTH-001")
    assert scoped["executable_count"] == 0
    assert all(
        "duplicate_source_serial" in row["problems"]
        for row in scoped["rows"]
        if row["source_serial"] == "SYNTH-001"
    )

    empty_scope = normalize_batch_rows(rows[:1], execute_serial="")
    assert empty_scope["executable_count"] == 0
    assert any("empty_execute_serial_scope" in row["problems"] for row in empty_scope["blocked_rows"])


def test_batch_csv_and_json_dispatch_and_malformed_json() -> None:
    csv_rows = load_batch_input(EXAMPLE_CSV)
    assert len(csv_rows) == 2
    csv_plan = normalize_batch_rows(csv_rows)
    assert csv_plan["row_count"] == 2

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        good_json = tmp_path / "batch.json"
        good_json.write_text(
            json.dumps(
                {
                    "rows": [
                        {
                            "source_serial": "SYNTH-010",
                            "source_name": "Reader",
                            "expected_mac": "AA-BB-CC-DD-EE-10",
                            "observed_firmware": "2.0.15.260410",
                            "active_outdated": "Yes",
                            "target_firmware": "2.0.15.260522",
                            "action": "PLAN",
                        }
                    ]
                }
            ),
            encoding="utf-8",
        )
        assert len(load_batch_input(good_json)) == 1

        bad_json = tmp_path / "bad.json"
        bad_json.write_text(json.dumps({"not_rows": []}), encoding="utf-8")
        try:
            load_batch_input(bad_json)
            raise AssertionError("expected malformed JSON rejection")
        except ValueError as exc:
            assert "rows" in str(exc)

        completed = subprocess.run(
            [
                sys.executable,
                str(MODULE),
                "batch",
                "--input",
                str(EXAMPLE_CSV),
                "--output",
                str(tmp_path / "out.json"),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        assert completed.returncode == 0, completed.stderr
        assert (tmp_path / "out.json").is_file()


def test_cli_artifact_created_without_explicit_output() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        # Use module API write_receipt default path under repo survey/output.
        identity = resolve_target_identity(_unique_identity())
        receipt = write_receipt("identity", identity, None)
        assert receipt.is_file()
        assert "survey" in str(receipt).replace("\\", "/")
        assert "hh-cc-reader-firmware-roundtrip-identity-" in receipt.name


def test_batch_cmd_missing_option_values_fail_closed() -> None:
    if sys.platform != "win32":
        return
    completed = subprocess.run(
        f'"{BATCH_CMD}" "{EXAMPLE_CSV}" --execute-serial & if errorlevel 1 exit /b 1',
        check=False,
        capture_output=True,
        text=True,
        shell=True,
    )
    combined = completed.stdout + completed.stderr
    assert "requires a non-empty" in combined
    assert completed.returncode != 0

    completed2 = subprocess.run(
        f'"{BATCH_CMD}" "{EXAMPLE_CSV}" --output & if errorlevel 1 exit /b 1',
        check=False,
        capture_output=True,
        text=True,
        shell=True,
    )
    combined2 = completed2.stdout + completed2.stderr
    assert "requires a non-empty" in combined2
    assert completed2.returncode != 0


def test_p5_normalize_evaluate_not_weakened() -> None:
    normalized = normalize_packet(load_packet_or_template(TEMPLATE))
    result = evaluate(normalized["evaluator_inputs"])
    assert result["packet_state"] == "BLOCKED_AUTHORITY"
    assert result["next_gate"] == "AUTHORIZED_READONLY_SESSION"
    assert result["mutation_authorized"] is False


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


if __name__ == "__main__":
    tests = [
        test_module_launchers_and_example_exist,
        test_tracked_docs_have_no_prohibited_live_identifiers,
        test_ambiguous_and_readerunk_identity_fail_closed,
        test_identity_tranches_preserve_strict_mutation_gate,
        test_strict_mac_validation_rejects_garbage_hex_extraction,
        test_cross_device_receipt_binding_fail_closed,
        test_missing_baseline_blocks_mutation_and_compare,
        test_roundtrip_requires_forward_mutation_before_restore_proof,
        test_policy_default_target_is_authoritative,
        test_batch_duplicate_groups_block_all_members_and_scope,
        test_batch_csv_and_json_dispatch_and_malformed_json,
        test_cli_artifact_created_without_explicit_output,
        test_batch_cmd_missing_option_values_fail_closed,
        test_p5_normalize_evaluate_not_weakened,
        test_eligibility_does_not_invent_outdated_from_version_order_alone,
    ]
    failures = 0
    for test in tests:
        try:
            test()
            print(f"PASS {test.__name__}")
        except Exception as exc:  # noqa: BLE001
            failures += 1
            print(f"FAIL {test.__name__}: {exc}")
    raise SystemExit(1 if failures else 0)
