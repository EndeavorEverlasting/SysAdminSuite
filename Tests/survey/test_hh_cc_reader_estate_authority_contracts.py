#!/usr/bin/env python3
"""Executable call-stack contracts for H&H estate-authority PROVEN_PATH seams."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_estate_authority import evaluate, load_policy

POLICY = ROOT / "harness/api/hh-cc-reader-firmware-policy.json"
EVALUATOR = ROOT / "harness/api/hh_cc_reader_estate_authority.py"


def read(path: Path) -> str:
    assert path.is_file(), f"missing estate-authority component: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def checklist_all_true(policy: dict) -> dict:
    return {item["id"]: True for item in policy["readonly_estate_checklist"]["items"]}


def complete_observation(**overrides) -> dict:
    policy = load_policy()
    inputs = {
        "mechanism_id": "paxstore-ota-push",
        "current_disposition": "CREDENTIAL_GATE",
        "authorized_readonly_session": True,
        "role_scope_ok": True,
        "mutation_intent": False,
        "mutation_actions_observed": [],
        "reader_identity_ref": "ext-reader-index-001",
        "representative_terminal_bound": True,
        "current_firmware_observed": True,
        "management_owner": "H&H estate tenant as shown on surface",
        "package_exposed_for_target": "YES",
        "package_release_id": "firmware-list-id-sanitized",
        "unknown_reasons": {},
        "assignment_method": "terminal push affordance observed; not invoked",
        "reboot_reconnect_behavior": "reboot then reconnect per surface text",
        "rollback_exception_path": "cancel/rollback path recorded from surface",
        "post_update_acceptance": "management and device version strings match target",
        "access_state": "PROVEN_ACCESS",
        "authority_packet_id": "pkt-readonly-001",
        "checklist_satisfied": checklist_all_true(policy),
        "target_firmware_planning_candidate": policy["selection"]["default_target"],
    }
    inputs.update(overrides)
    return inputs


def test_success_stack_promotes_proven_path_without_mutation_authority() -> None:
    result = evaluate(complete_observation())
    assert result["packet_state"] == "COMPLETE"
    assert result["proposed_disposition"] == "PROVEN_PATH"
    assert result["disposition_may_promote"] is True
    assert result["mutation_authorized"] is False
    assert result["package_conflict"] is False
    assert result["reason"] == "PROVEN_PATH_ACCEPTANCE_SATISFIED"
    assert result["next_gate"] == "P6_SEPARATE_PILOT_AUTHORIZATION"
    assert result["call_stack"][0] == "OPERATOR_READONLY_OBSERVATION"
    assert result["call_stack"][-1] == "RESULT_PROVEN_PATH_MUTATION_DENIED"
    assert "evaluate_proven_path_transition" in result["call_stack"]


def test_package_absence_is_conflict_not_silent_substitution() -> None:
    result = evaluate(
        complete_observation(
            package_exposed_for_target="NO",
            package_release_id="NONE_OBSERVED",
        )
    )
    assert result["packet_state"] == "COMPLETE"
    assert result["proposed_disposition"] == "PROVEN_PATH"
    assert result["disposition_may_promote"] is True
    assert result["mutation_authorized"] is False
    assert result["package_conflict"] is True
    assert result["reason"] == "PROVEN_PATH_WITH_PACKAGE_CONFLICT"
    assert result["next_gate"] == "RESOLVE_PACKAGE_CONFLICT_BEFORE_P6"


def test_failure_stack_blocks_without_readonly_session() -> None:
    result = evaluate(
        complete_observation(
            authorized_readonly_session=False,
            access_state="BLOCKED_AUTHORITY",
        )
    )
    assert result["packet_state"] == "BLOCKED_AUTHORITY"
    assert result["proposed_disposition"] == "CREDENTIAL_GATE"
    assert result["disposition_may_promote"] is False
    assert result["mutation_authorized"] is False
    assert result["reason"] == "AUTHORIZED_READONLY_SESSION_REQUIRED"
    assert "RESULT_BLOCKED_AUTHORITY" in result["call_stack"]


def test_failure_stack_rejects_discovery_mutation() -> None:
    result = evaluate(
        complete_observation(
            mutation_intent=True,
            mutation_actions_observed=["push"],
        )
    )
    assert result["packet_state"] == "REJECTED"
    assert result["disposition_may_promote"] is False
    assert result["mutation_authorized"] is False
    assert result["reason"] == "DISCOVERY_MUTATION_FORBIDDEN"
    assert "RESULT_REJECTED_MUTATION" in result["call_stack"]


def test_failure_stack_keeps_incomplete_packet_at_credential_gate() -> None:
    result = evaluate(
        complete_observation(
            management_owner=None,
            assignment_method="UNKNOWN",
            unknown_reasons={},
        )
    )
    assert result["packet_state"] == "INCOMPLETE"
    assert result["proposed_disposition"] == "CREDENTIAL_GATE"
    assert result["disposition_may_promote"] is False
    assert result["reason"] == "PACKET_FIELDS_INCOMPLETE"
    assert "MANAGEMENT_OWNER" in result["unanswered_packet_fields"]
    assert "ASSIGNMENT_METHOD" in result["unanswered_packet_fields"]


def test_ineligible_local_tms_cannot_promote() -> None:
    result = evaluate(complete_observation(mechanism_id="terminal-tms-pull"))
    assert result["packet_state"] == "REJECTED"
    assert result["proposed_disposition"] == "NOT_APPLICABLE"
    assert result["disposition_may_promote"] is False
    assert result["reason"] == "MECHANISM_INELIGIBLE"


def test_policy_owns_acceptance_record_and_checklist() -> None:
    policy = load(POLICY)
    acceptance = policy["proven_path_acceptance"]
    checklist = policy["readonly_estate_checklist"]
    assert acceptance["from_disposition"] == "CREDENTIAL_GATE"
    assert acceptance["to_disposition"] == "PROVEN_PATH"
    assert "payment-fusion-control-center" in acceptance["eligible_mechanism_ids"]
    assert "paxstore-ota-push" in acceptance["eligible_mechanism_ids"]
    assert "terminal-tms-pull" in acceptance["ineligible_mechanism_ids"]
    assert acceptance["required_access_state"] == "PROVEN_ACCESS"
    assert len(acceptance["required_packet_fields"]) == 7
    assert all(acceptance["rules"].values())
    assert checklist["lane"] == "P5_management_plane_discovery"
    assert "push" in checklist["forbidden_actions"]
    assert "Readonly Firmware List + Terminal Management" in checklist["minimum_role_by_surface"]["paxstore-ota-push"]
    assert [item["order"] for item in checklist["items"]] == list(range(1, 13))
    assert EVALUATOR.is_file()
    text = read(EVALUATOR)
    assert "evaluate_proven_path_transition" in text
    assert "DISCOVERY_MUTATION_FORBIDDEN" in text


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for fn in tests:
        fn()
    print(f"PASS: H&H estate-authority PROVEN_PATH call-stack contracts ({len(tests)} groups)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
