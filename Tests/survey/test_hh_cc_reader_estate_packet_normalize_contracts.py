#!/usr/bin/env python3
"""Executable call-stack contracts for P5-B packet normalization."""
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_estate_packet_normalize import (
    derive_checklist_satisfied,
    generate_authority_packet_id,
    load_packet_or_template,
    normalize_packet,
    remaining_live_worksheet,
    sanitize_reader_identity_ref,
)
from harness.api.hh_cc_reader_estate_authority import evaluate, load_policy

TEMPLATE = ROOT / "docs/examples/hh-cc-reader-proven-path-authority-packet.template.json"
CMD = ROOT / "Normalize-HHCCReaderEstatePacket.cmd"
MODULE = ROOT / "harness/api/hh_cc_reader_estate_packet_normalize.py"


def test_module_and_launcher_exist() -> None:
    assert MODULE.is_file()
    assert CMD.is_file()
    text = CMD.read_text(encoding="utf-8-sig")
    assert "hh_cc_reader_estate_packet_normalize.py" in text
    assert "Never invent" in text or "never invent" in text.lower() or "No Payment Fusion" in text


def test_normalize_settles_derivable_without_inventing_live() -> None:
    packet = load_packet_or_template(TEMPLATE)
    before_fw = packet["evaluator_inputs"].get("current_firmware_value")
    before_pkg = packet["evaluator_inputs"].get("package_exposed_for_target")
    normalized = normalize_packet(packet)
    inputs = normalized["evaluator_inputs"]
    assert inputs["mechanism_id"] == "payment-fusion-control-center"
    assert inputs["current_disposition"] == "CREDENTIAL_GATE"
    assert inputs["mutation_intent"] is False
    assert inputs["mutation_actions_observed"] == []
    assert inputs["target_firmware_planning_candidate"] == "2.0.15.260522"
    assert isinstance(inputs["authority_packet_id"], str) and inputs["authority_packet_id"]
    assert inputs["current_firmware_value"] == before_fw
    assert inputs["package_exposed_for_target"] == before_pkg
    assert inputs["package_release_id"] in {None, "UNKNOWN"}
    assert inputs["authorized_readonly_session"] is False
    assert normalized["_p5b_normalization"]["invented_live_values"] is False
    remaining = remaining_live_worksheet(inputs)
    ids = {item["id"] for item in remaining}
    assert "authenticated_estate_access" in ids
    assert "current_firmware_value" in ids
    assert "target_package_exposed" in ids


def test_normalize_then_evaluate_reaches_authorized_readonly_gate() -> None:
    normalized = normalize_packet(load_packet_or_template(TEMPLATE))
    result = evaluate(normalized["evaluator_inputs"])
    assert result["packet_state"] == "BLOCKED_AUTHORITY"
    assert result["proposed_disposition"] == "CREDENTIAL_GATE"
    assert result["next_gate"] == "AUTHORIZED_READONLY_SESSION"
    assert result["mutation_authorized"] is False
    assert result["call_stack"][0] == "OPERATOR_READONLY_OBSERVATION"
    assert result["call_stack"][-1] == "RESULT_BLOCKED_AUTHORITY"


def test_sanitize_reader_identity_ref_and_checklist_derivation() -> None:
    ref = sanitize_reader_identity_ref("lab-a80-index-07")
    assert ref.startswith("ext-")
    try:
        sanitize_reader_identity_ref("http://evil.example/x")
        raise AssertionError("expected secret-bearing key rejection")
    except ValueError:
        pass
    try:
        # Construct rather than embed an IPv4 literal in tracked source.
        sanitize_reader_identity_ref(".".join(["10", "1", "2", "3"]) + "-reader")
        raise AssertionError("expected IPv4 rejection")
    except ValueError:
        pass

    policy = load_policy()
    inputs = normalize_packet(load_packet_or_template(TEMPLATE))["evaluator_inputs"]
    inputs.update(
        {
            "authorized_readonly_session": True,
            "role_scope_ok": True,
            "representative_terminal_bound": True,
            "reader_identity_ref": ref,
            "current_firmware_observed": True,
            "current_firmware_value": "2.0.14.221110",
            "management_owner": "H&H estate tenant as shown on surface",
            "package_exposed_for_target": "NO",
            "package_release_id": "NONE_OBSERVED",
            "assignment_method": "automatic terminal updating affordance observed; not invoked",
            "reboot_reconnect_behavior": "reboot then reconnect per surface text",
            "rollback_exception_path": "cancel path recorded from surface",
            "post_update_acceptance": "management and device version strings match target",
            "access_state": "PROVEN_ACCESS",
        }
    )
    checklist = derive_checklist_satisfied(inputs, policy)
    assert checklist["confirm-authorized-readonly-session"] is True
    assert checklist["observe-current-firmware"] is True
    assert checklist["resolve-target-package-visibility"] is True
    assert checklist["emit-sanitized-authority-packet"] is True
    remaining = remaining_live_worksheet(inputs)
    assert remaining == []


def test_release_reference_absence_routes_p5d_without_false_resolution() -> None:
    policy = load_policy()
    packet = load_packet_or_template(TEMPLATE)
    packet["evaluator_inputs"]["package_exposed_for_target"] = "YES"
    packet["evaluator_inputs"]["package_release_id"] = "UNKNOWN_SURFACE_NOT_EXPOSED"
    normalized = normalize_packet(packet)
    inputs = normalized["evaluator_inputs"]

    checklist = derive_checklist_satisfied(inputs, policy)
    assert checklist["resolve-target-package-visibility"] is False
    remaining_ids = {item["id"] for item in remaining_live_worksheet(inputs)}
    assert "package_release_reference" in remaining_ids
    assert normalized["_p5b_normalization"]["p5d_release_reference_compatibility_repair_required"] is True

    # Complete the other live fields so the evaluator reaches the release-reference discriminator.
    inputs.update(
        {
            "authorized_readonly_session": True,
            "role_scope_ok": True,
            "representative_terminal_bound": True,
            "reader_identity_ref": "ext-hh-a80-p5d-test",
            "current_firmware_observed": True,
            "current_firmware_value": "2.0.14.221110",
            "management_owner": "H&H estate tenant as shown on surface",
            "assignment_method": "automatic terminal updating affordance observed; not invoked",
            "reboot_reconnect_behavior": "reboot then reconnect per surface text",
            "rollback_exception_path": "cancel path recorded from surface",
            "post_update_acceptance": "management and device version strings match target",
            "access_state": "PROVEN_ACCESS",
        }
    )
    inputs["checklist_satisfied"] = {
        item["id"]: True for item in policy["readonly_estate_checklist"]["items"]
    }
    result = evaluate(inputs)
    assert result["packet_state"] == "INCOMPLETE"
    assert result["reason"] == "RELEASE_REFERENCE_NOT_EXPOSED"
    assert result["next_gate"] == "P5D_RELEASE_REFERENCE_COMPATIBILITY_REPAIR"
    assert result["mutation_authorized"] is False


def test_package_no_uses_none_observed_without_triggering_p5d() -> None:
    packet = load_packet_or_template(TEMPLATE)
    packet["evaluator_inputs"]["package_exposed_for_target"] = "NO"
    packet["evaluator_inputs"]["package_release_id"] = "UNKNOWN"
    normalized = normalize_packet(packet)
    inputs = normalized["evaluator_inputs"]
    assert inputs["package_release_id"] == "NONE_OBSERVED"
    remaining_ids = {item["id"] for item in remaining_live_worksheet(inputs)}
    assert "package_release_reference" not in remaining_ids
    assert normalized["_p5b_normalization"]["p5d_release_reference_compatibility_repair_required"] is False


def test_cli_writes_external_packet_and_worksheet() -> None:
    from harness.api.hh_cc_reader_estate_packet_normalize import main as normalize_main

    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "packet.json"
        ws = Path(tmp) / "worksheet.md"
        code = normalize_main(["--output", str(out), "--worksheet", str(ws)])
        assert code == 0
        packet = json.loads(out.read_text(encoding="utf-8"))
        assert packet["evaluator_inputs"]["mechanism_id"] == "payment-fusion-control-center"
        assert "Authorized login/MFA reaches the H&H estate" in ws.read_text(encoding="utf-8")
        assert generate_authority_packet_id().startswith("hh-cc-p5-")


def main() -> int:
    test_module_and_launcher_exist()
    test_normalize_settles_derivable_without_inventing_live()
    test_normalize_then_evaluate_reaches_authorized_readonly_gate()
    test_sanitize_reader_identity_ref_and_checklist_derivation()
    test_release_reference_absence_routes_p5d_without_false_resolution()
    test_package_no_uses_none_observed_without_triggering_p5d()
    test_cli_writes_external_packet_and_worksheet()
    print("PASS: H&H estate-authority P5-B normalization call-stack contracts (7 groups)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
