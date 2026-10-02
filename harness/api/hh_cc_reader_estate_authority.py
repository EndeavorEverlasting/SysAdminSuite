"""Executable P5 estate-authority call-stack seams.

Evaluates sanitized read-only estate observations against the machine firmware
policy's PROVEN_PATH acceptance record and read-only estate checklist.

This module is the program seam between repository doctrine and later portal
adapters. It never contacts Payment Fusion, PAXSTORE, or any network surface.
Live terminal identifiers and credentials must stay outside Git inputs.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_POLICY_PATH = ROOT / "harness" / "api" / "hh-cc-reader-firmware-policy.json"

ANSWERED_PACKAGE_EXPOSED = frozenset({"YES", "NO"})
UNKNOWN_MARKERS = frozenset({"UNKNOWN", "", "NONE", "N/A"})
PACKAGE_EXPOSED_FIELD = "PACKAGE_EXPOSED_FOR_2_0_15_260522"

_DEFAULTS: dict[str, Any] = {
    "mechanism_id": None,
    "current_disposition": "CREDENTIAL_GATE",
    "authorized_readonly_session": False,
    "role_scope_ok": False,
    "mutation_intent": False,
    "mutation_actions_observed": (),
    "reader_identity_ref": None,
    "representative_terminal_bound": False,
    "current_firmware_observed": False,
    "current_firmware_value": None,
    "management_owner": None,
    "package_exposed_for_target": "UNKNOWN",
    "package_release_id": "UNKNOWN",
    "unknown_reasons": {},
    "assignment_method": None,
    "reboot_reconnect_behavior": None,
    "rollback_exception_path": None,
    "post_update_acceptance": None,
    "access_state": "ACCESS_NOT_PROVEN",
    "authority_packet_id": None,
    "checklist_satisfied": {},
    "target_firmware_planning_candidate": None,
}


def load_policy(path: Path = DEFAULT_POLICY_PATH) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    required = {
        "schema_version",
        "selection",
        "mechanism_discovery",
        "proven_path_acceptance",
        "readonly_estate_checklist",
    }
    missing = required - data.keys()
    assert not missing, f"firmware policy missing estate-authority fields: {sorted(missing)}"
    assert data["schema_version"] == "sas-hh-cc-reader-firmware-policy/v1"
    return data


def _answered(value: Any, unknown_reasons: dict[str, Any], field: str) -> bool:
    if value is None:
        return False
    text = str(value).strip()
    if text.upper() in UNKNOWN_MARKERS or text.upper().startswith("UNKNOWN"):
        reason = unknown_reasons.get(field)
        return isinstance(reason, str) and len(reason.strip()) >= 8
    return len(text) >= 1


def _resolved_firmware_value(value: Any) -> str | None:
    """Return a sanitized authoritative firmware string, or None if unresolved."""
    if value is None or isinstance(value, bool):
        return None
    text = str(value).strip()
    if not text:
        return None
    upper = text.upper()
    if upper in UNKNOWN_MARKERS or upper.startswith("UNKNOWN"):
        return None
    return text


def _normalize_actions(actions: Any) -> set[str]:
    if actions is None:
        return set()
    if isinstance(actions, str):
        return {actions.strip().lower()} if actions.strip() else set()
    return {str(item).strip().lower() for item in actions if str(item).strip()}


def _result(*, current_firmware_observed_value: str | None = None, **kwargs: Any) -> dict[str, Any]:
    return {
        "current_firmware_observed_value": current_firmware_observed_value,
        **kwargs,
    }


def evaluate(inputs: dict[str, Any], policy: dict[str, Any] | None = None) -> dict[str, Any]:
    """Trace the P5 estate-authority call stack for one sanitized observation.

    Call stack (success path):
      OPERATOR_READONLY_OBSERVATION
        -> validate_session_and_role
        -> reject_forbidden_mutation
        -> bind_representative_terminal
        -> score_readonly_checklist
        -> assemble_authority_packet
        -> evaluate_proven_path_transition
        -> RESULT (disposition proposal + mutation still denied)

    Failure paths classify incomplete packet, blocked authority, ineligible
    mechanism, package conflict without substitution, and mutation rejection.
    """
    policy = policy if policy is not None else load_policy()
    unknown = set(inputs) - set(_DEFAULTS)
    if unknown:
        raise ValueError(f"unknown estate-authority inputs: {sorted(unknown)}")
    data = {**_DEFAULTS, **inputs}

    acceptance = policy["proven_path_acceptance"]
    checklist = policy["readonly_estate_checklist"]
    default_target = policy["selection"]["default_target"]
    eligible = set(acceptance["eligible_mechanism_ids"])
    ineligible = set(acceptance["ineligible_mechanism_ids"])
    forbidden = {str(item).lower() for item in checklist["forbidden_actions"]}
    required_items = [item["id"] for item in checklist["items"] if item.get("required")]
    packet_fields = {
        "MANAGEMENT_OWNER": data["management_owner"],
        "PACKAGE_EXPOSED_FOR_2_0_15_260522": data["package_exposed_for_target"],
        "PACKAGE_RELEASE_ID": data["package_release_id"],
        "ASSIGNMENT_METHOD": data["assignment_method"],
        "REBOOT_RECONNECT_BEHAVIOR": data["reboot_reconnect_behavior"],
        "ROLLBACK_EXCEPTION_PATH": data["rollback_exception_path"],
        "POST_UPDATE_ACCEPTANCE": data["post_update_acceptance"],
    }
    unknown_reasons = dict(data["unknown_reasons"] or {})
    mutation_actions = _normalize_actions(data["mutation_actions_observed"])
    checklist_satisfied = {
        str(key): bool(value) for key, value in dict(data["checklist_satisfied"] or {}).items()
    }
    missing_checklist = [item_id for item_id in required_items if not checklist_satisfied.get(item_id)]
    target = data["target_firmware_planning_candidate"] or default_target
    if target != default_target:
        return _result(
            packet_state="REJECTED",
            proposed_disposition=data["current_disposition"],
            disposition_may_promote=False,
            mutation_authorized=False,
            package_conflict=False,
            fail_closed=True,
            reason="TARGET_FIRMWARE_MISMATCH",
            checklist_missing=missing_checklist,
            next_gate="ALIGN_PLANNING_CANDIDATE_TO_POLICY",
            call_stack=[
                "OPERATOR_READONLY_OBSERVATION",
                "validate_planning_candidate",
                "RESULT_REJECTED_TARGET_MISMATCH",
            ],
        )

    # --- validate_session_and_role ---
    mechanism_id = data["mechanism_id"]
    if mechanism_id is None:
        raise ValueError("mechanism_id is required")
    mechanism_id = str(mechanism_id)
    if mechanism_id in ineligible:
        return _result(
            packet_state="REJECTED",
            proposed_disposition="NOT_APPLICABLE",
            disposition_may_promote=False,
            mutation_authorized=False,
            package_conflict=False,
            fail_closed=True,
            reason="MECHANISM_INELIGIBLE",
            checklist_missing=missing_checklist,
            next_gate="USE_ELIGIBLE_CREDENTIAL_GATE_SURFACE",
            call_stack=[
                "OPERATOR_READONLY_OBSERVATION",
                "validate_session_and_role",
                "RESULT_REJECTED_INELIGIBLE_MECHANISM",
            ],
        )
    if mechanism_id not in eligible:
        raise ValueError(f"unknown mechanism_id: {mechanism_id}")

    # --- reject_forbidden_mutation ---
    if bool(data["mutation_intent"]) or (mutation_actions & forbidden):
        return _result(
            packet_state="REJECTED",
            proposed_disposition=data["current_disposition"],
            disposition_may_promote=False,
            mutation_authorized=False,
            package_conflict=False,
            fail_closed=True,
            reason="DISCOVERY_MUTATION_FORBIDDEN",
            checklist_missing=missing_checklist,
            next_gate="RESTART_READ_ONLY_OBSERVATION",
            call_stack=[
                "OPERATOR_READONLY_OBSERVATION",
                "validate_session_and_role",
                "reject_forbidden_mutation",
                "RESULT_REJECTED_MUTATION",
            ],
        )

    if data["access_state"] == "BLOCKED_AUTHORITY" or not bool(data["authorized_readonly_session"]):
        return _result(
            packet_state="BLOCKED_AUTHORITY",
            proposed_disposition="CREDENTIAL_GATE",
            disposition_may_promote=False,
            mutation_authorized=False,
            package_conflict=False,
            fail_closed=False,
            reason="AUTHORIZED_READONLY_SESSION_REQUIRED",
            checklist_missing=missing_checklist,
            next_gate="AUTHORIZED_READONLY_SESSION",
            call_stack=[
                "OPERATOR_READONLY_OBSERVATION",
                "validate_session_and_role",
                "reject_forbidden_mutation",
                "RESULT_BLOCKED_AUTHORITY",
            ],
        )

    if not bool(data["role_scope_ok"]):
        return _result(
            packet_state="INCOMPLETE",
            proposed_disposition="CREDENTIAL_GATE",
            disposition_may_promote=False,
            mutation_authorized=False,
            package_conflict=False,
            fail_closed=False,
            reason="MINIMUM_READ_ROLE_UNSATISFIED",
            checklist_missing=missing_checklist,
            next_gate="CONFIRM_MINIMUM_READ_ROLE",
            call_stack=[
                "OPERATOR_READONLY_OBSERVATION",
                "validate_session_and_role",
                "reject_forbidden_mutation",
                "RESULT_INCOMPLETE_ROLE",
            ],
        )

    # --- bind_representative_terminal ---
    reader_ref = data["reader_identity_ref"]
    if not bool(data["representative_terminal_bound"]) or not _answered(
        reader_ref, unknown_reasons, "READER_IDENTITY_REF"
    ):
        return _result(
            packet_state="INCOMPLETE",
            proposed_disposition="CREDENTIAL_GATE",
            disposition_may_promote=False,
            mutation_authorized=False,
            package_conflict=False,
            fail_closed=False,
            reason="REPRESENTATIVE_TERMINAL_UNBOUND",
            checklist_missing=missing_checklist,
            next_gate="BIND_REPRESENTATIVE_A80",
            call_stack=[
                "OPERATOR_READONLY_OBSERVATION",
                "validate_session_and_role",
                "reject_forbidden_mutation",
                "bind_representative_terminal",
                "RESULT_INCOMPLETE_TERMINAL_BIND",
            ],
        )

    if not bool(data["current_firmware_observed"]):
        return _result(
            packet_state="INCOMPLETE",
            proposed_disposition="CREDENTIAL_GATE",
            disposition_may_promote=False,
            mutation_authorized=False,
            package_conflict=False,
            fail_closed=False,
            reason="CURRENT_FIRMWARE_NOT_OBSERVED",
            checklist_missing=missing_checklist,
            next_gate="OBSERVE_CURRENT_FIRMWARE",
            call_stack=[
                "OPERATOR_READONLY_OBSERVATION",
                "validate_session_and_role",
                "reject_forbidden_mutation",
                "bind_representative_terminal",
                "RESULT_INCOMPLETE_CURRENT_FIRMWARE",
            ],
        )

    firmware_value = _resolved_firmware_value(data["current_firmware_value"])
    if firmware_value is None:
        return _result(
            packet_state="INCOMPLETE",
            proposed_disposition="CREDENTIAL_GATE",
            disposition_may_promote=False,
            mutation_authorized=False,
            package_conflict=False,
            fail_closed=False,
            reason="CURRENT_FIRMWARE_VALUE_REQUIRED",
            checklist_missing=missing_checklist,
            next_gate="RECORD_CURRENT_FIRMWARE_VALUE",
            call_stack=[
                "OPERATOR_READONLY_OBSERVATION",
                "validate_session_and_role",
                "reject_forbidden_mutation",
                "bind_representative_terminal",
                "RESULT_INCOMPLETE_CURRENT_FIRMWARE_VALUE",
            ],
        )

    # --- score_readonly_checklist ---
    if missing_checklist:
        return _result(
            current_firmware_observed_value=firmware_value,
            packet_state="INCOMPLETE",
            proposed_disposition="CREDENTIAL_GATE",
            disposition_may_promote=False,
            mutation_authorized=False,
            package_conflict=False,
            fail_closed=False,
            reason="CHECKLIST_INCOMPLETE",
            checklist_missing=missing_checklist,
            next_gate="COMPLETE_READONLY_CHECKLIST",
            call_stack=[
                "OPERATOR_READONLY_OBSERVATION",
                "validate_session_and_role",
                "reject_forbidden_mutation",
                "bind_representative_terminal",
                "score_readonly_checklist",
                "RESULT_INCOMPLETE_CHECKLIST",
            ],
        )

    # --- assemble_authority_packet ---
    # Package visibility may be recorded as UNKNOWN+reason for checklist observation,
    # but completion_gate promotion requires YES or NO only.
    unanswered = [
        field
        for field, value in packet_fields.items()
        if field != PACKAGE_EXPOSED_FIELD and not _answered(value, unknown_reasons, field)
    ]
    package_exposed = str(data["package_exposed_for_target"]).strip().upper()
    release_id = str(data["package_release_id"]).strip()
    package_conflict = package_exposed == "NO"
    if package_exposed == "YES" and (
        release_id.upper() in UNKNOWN_MARKERS or release_id.upper() == "NONE_OBSERVED"
    ):
        unanswered.append("PACKAGE_RELEASE_ID")
    if package_exposed not in ANSWERED_PACKAGE_EXPOSED:
        unanswered.append(PACKAGE_EXPOSED_FIELD)

    if unanswered:
        return _result(
            current_firmware_observed_value=firmware_value,
            packet_state="INCOMPLETE",
            proposed_disposition="CREDENTIAL_GATE",
            disposition_may_promote=False,
            mutation_authorized=False,
            package_conflict=package_conflict,
            fail_closed=bool(acceptance["rules"]["unknown_without_reason_fails_closed"]),
            reason="PACKET_FIELDS_INCOMPLETE",
            checklist_missing=[],
            unanswered_packet_fields=unanswered,
            next_gate="COMPLETE_ESTATE_AUTHORITY_PACKET",
            call_stack=[
                "OPERATOR_READONLY_OBSERVATION",
                "validate_session_and_role",
                "reject_forbidden_mutation",
                "bind_representative_terminal",
                "score_readonly_checklist",
                "assemble_authority_packet",
                "RESULT_INCOMPLETE_PACKET",
            ],
        )

    if data["access_state"] != acceptance["required_access_state"]:
        return _result(
            current_firmware_observed_value=firmware_value,
            packet_state="INCOMPLETE",
            proposed_disposition="CREDENTIAL_GATE",
            disposition_may_promote=False,
            mutation_authorized=False,
            package_conflict=package_conflict,
            fail_closed=False,
            reason="ACCESS_STATE_NOT_PROVEN",
            checklist_missing=[],
            next_gate="SET_ACCESS_STATE_PROVEN_ACCESS",
            call_stack=[
                "OPERATOR_READONLY_OBSERVATION",
                "validate_session_and_role",
                "reject_forbidden_mutation",
                "bind_representative_terminal",
                "score_readonly_checklist",
                "assemble_authority_packet",
                "RESULT_ACCESS_NOT_PROVEN",
            ],
        )

    if not _answered(data["authority_packet_id"], unknown_reasons, "AUTHORITY_PACKET_ID"):
        return _result(
            current_firmware_observed_value=firmware_value,
            packet_state="INCOMPLETE",
            proposed_disposition="CREDENTIAL_GATE",
            disposition_may_promote=False,
            mutation_authorized=False,
            package_conflict=package_conflict,
            fail_closed=False,
            reason="AUTHORITY_PACKET_ID_REQUIRED",
            checklist_missing=[],
            next_gate="EMIT_SANITIZED_AUTHORITY_PACKET",
            call_stack=[
                "OPERATOR_READONLY_OBSERVATION",
                "validate_session_and_role",
                "reject_forbidden_mutation",
                "bind_representative_terminal",
                "score_readonly_checklist",
                "assemble_authority_packet",
                "RESULT_MISSING_PACKET_ID",
            ],
        )

    # --- evaluate_proven_path_transition ---
    # Package NO is an explicit conflict, not a silent substitution, and may
    # still prove the management path while blocking pilot package authority.
    next_gate = (
        "RESOLVE_PACKAGE_CONFLICT_BEFORE_P6"
        if package_conflict
        else "P6_SEPARATE_PILOT_AUTHORIZATION"
    )
    return _result(
        current_firmware_observed_value=firmware_value,
        packet_state="COMPLETE",
        proposed_disposition=acceptance["to_disposition"],
        disposition_may_promote=True,
        mutation_authorized=False,
        package_conflict=package_conflict,
        fail_closed=False,
        reason="PROVEN_PATH_ACCEPTANCE_SATISFIED"
        if not package_conflict
        else "PROVEN_PATH_WITH_PACKAGE_CONFLICT",
        checklist_missing=[],
        unanswered_packet_fields=[],
        next_gate=next_gate,
        call_stack=[
            "OPERATOR_READONLY_OBSERVATION",
            "validate_session_and_role",
            "reject_forbidden_mutation",
            "bind_representative_terminal",
            "score_readonly_checklist",
            "assemble_authority_packet",
            "evaluate_proven_path_transition",
            "RESULT_PROVEN_PATH_MUTATION_DENIED",
        ],
    )
