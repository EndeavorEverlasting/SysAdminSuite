#!/usr/bin/env python3
"""P95 additive firmware-protocol selector and read-only dispatcher.

Ranks the next observation protocol from site/device evidence while preserving
all configured paths. Selection and dispatch never perform or authorize a live
firmware mutation.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "harness/api/hh-cc-reader-firmware-protocols.v1.json"
SCHEMA = "sas-hh-cc-reader-firmware-protocol-selection/v1"
DISPATCH_SCHEMA = "sas-hh-cc-reader-firmware-protocol-dispatch/v1"
RECEIPT_SCHEMA = "sas-hh-cc-reader-firmware-protocol-receipt/v1"
DEFAULT_RECEIPT_DIR = ROOT / "survey/output/hh-cc-reader"


class FirmwareProtocolError(ValueError):
    """Raised when protocol configuration or selection input is invalid."""


def _string_list(value: Any, field: str) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list) or any(
        not isinstance(item, str) or not item.strip() for item in value
    ):
        raise FirmwareProtocolError(f"{field}_must_be_string_array")
    normalized = [item.strip() for item in value]
    if len(normalized) != len(set(normalized)):
        raise FirmwareProtocolError(f"{field}_must_not_contain_duplicates")
    return normalized


def load_protocol_contract(path: Path = CONTRACT) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise FirmwareProtocolError("protocol_contract_root_must_be_object")
    if payload.get("schema_version") != "sas-hh-cc-reader-firmware-protocols/v1":
        raise FirmwareProtocolError("unsupported_protocol_contract")
    if payload.get("status") != "IMPLEMENTED":
        raise FirmwareProtocolError("protocol_contract_not_implemented")

    protocols = payload.get("protocols")
    if not isinstance(protocols, dict) or not protocols:
        raise FirmwareProtocolError("protocol_catalog_required")

    default_order = payload.get("default_preference_order")
    if not isinstance(default_order, list):
        raise FirmwareProtocolError("default_preference_order_required")
    if len(default_order) != len(set(default_order)):
        raise FirmwareProtocolError("default_preference_order_has_duplicates")
    if set(default_order) != set(protocols):
        raise FirmwareProtocolError("default_preference_order_must_cover_catalog")

    profile_contract = payload.get("site_profile_contract")
    if not isinstance(profile_contract, dict):
        raise FirmwareProtocolError("site_profile_contract_required")
    if profile_contract.get("required_for_mutation_readiness") is not True:
        raise FirmwareProtocolError("site_profile_must_gate_mutation_readiness")

    for protocol_id, spec in protocols.items():
        if not isinstance(spec, dict):
            raise FirmwareProtocolError(f"protocol_spec_invalid:{protocol_id}")
        for field in (
            "label",
            "control_plane",
            "operational_tier",
            "observation_capabilities",
            "mutation_capabilities",
            "required_evidence_any",
            "required_authority_for_mutation",
            "required_gates_for_mutation",
            "observation_dispatch",
            "presentation_role",
        ):
            if field not in spec:
                raise FirmwareProtocolError(f"protocol_field_missing:{protocol_id}:{field}")
        _string_list(spec["observation_capabilities"], f"{protocol_id}.observation_capabilities")
        _string_list(spec["mutation_capabilities"], f"{protocol_id}.mutation_capabilities")
        evidence = _string_list(spec["required_evidence_any"], f"{protocol_id}.required_evidence_any")
        if not evidence:
            raise FirmwareProtocolError(f"protocol_evidence_signal_required:{protocol_id}")
        _string_list(spec["required_authority_for_mutation"], f"{protocol_id}.required_authority_for_mutation")
        _string_list(spec["required_gates_for_mutation"], f"{protocol_id}.required_gates_for_mutation")
        dispatch = spec["observation_dispatch"]
        if not isinstance(dispatch, dict) or not str(dispatch.get("mode") or "").strip():
            raise FirmwareProtocolError(f"observation_dispatch_invalid:{protocol_id}")
        if not str(dispatch.get("next_action") or "").strip():
            raise FirmwareProtocolError(f"observation_dispatch_action_required:{protocol_id}")

    invariants = payload.get("invariants", {})
    for required_true in (
        "protocols_are_additive_not_mutually_destructive",
        "site_specific_preference_may_reorder_protocols",
        "unobserved_protocols_remain_preserved",
        "selection_never_authorizes_mutation",
        "lab_only_protocols_never_auto_select_for_production",
        "paxstore_is_default_fallback_not_global_default",
        "unknown_or_unproven_site_profile_blocks_mutation_readiness",
        "observation_dispatch_never_performs_mutation",
        "presentation_is_projection_not_authority",
        "version_evidence_capture_defaults_fail_closed",
        "presentation_projection_never_promotes_technical_evidence",
    ):
        if invariants.get(required_true) is not True:
            raise FirmwareProtocolError(f"required_invariant_missing:{required_true}")

    capture_contract = payload.get("version_evidence_capture_contract")
    if not isinstance(capture_contract, dict):
        raise FirmwareProtocolError("version_evidence_capture_contract_required")
    if capture_contract.get("schema_version") != "sas-hh-cc-reader-kiosk4-version-evidence-capture/v1":
        raise FirmwareProtocolError("version_evidence_capture_schema_invalid")
    if capture_contract.get("default_capture_state") != "AWAITING_FIELD_OBSERVATION":
        raise FirmwareProtocolError("version_evidence_capture_default_must_fail_closed")
    if capture_contract.get("classifier_input_key") != "labeled_observations":
        raise FirmwareProtocolError("version_evidence_capture_classifier_input_invalid")
    if capture_contract.get("classifier_required_observation_fields") != ["section", "field_heading", "value"]:
        raise FirmwareProtocolError("version_evidence_capture_classifier_keys_invalid")
    capture_rules = capture_contract.get("rules")
    if not isinstance(capture_rules, dict):
        raise FirmwareProtocolError("version_evidence_capture_rules_required")
    for rule in (
        "template_contains_no_live_identity",
        "template_contains_no_current_firmware_value",
        "template_labeled_observations_start_empty",
        "campaign_target_must_not_be_prefilled_as_current",
        "capture_must_use_classifier_native_keys",
        "mutation_authorized_must_default_false",
        "presentation_projection_is_downstream_only",
        "presentation_may_not_infer_missing_firmware_or_baseline_state",
    ):
        if capture_rules.get(rule) is not True:
            raise FirmwareProtocolError(f"version_evidence_capture_rule_missing:{rule}")

    showcase = payload.get("presentation_showcase_contract")
    if not isinstance(showcase, dict):
        raise FirmwareProtocolError("presentation_showcase_contract_required")
    showcase_rules = showcase.get("rules")
    if not isinstance(showcase_rules, dict):
        raise FirmwareProtocolError("presentation_showcase_rules_required")
    for rule in (
        "presentation_is_not_a_technical_authority",
        "only_typed_source_states_may_be_projected",
        "unknown_and_blocked_states_must_remain_explicit",
        "downstream_presentation_cannot_select_protocol_or_authorize_mutation",
        "successful_visual_narrative_must_not_promote_unproven_runtime_state",
    ):
        if showcase_rules.get(rule) is not True:
            raise FirmwareProtocolError(f"presentation_showcase_rule_missing:{rule}")
    projection = showcase.get("state_projection")
    if not isinstance(projection, dict):
        raise FirmwareProtocolError("presentation_showcase_state_projection_required")
    expected_projection = {
        "AWAITING_FIELD_OBSERVATION": "BLOCKED_EVIDENCE",
        "INPUT_PATH_CLASSIFIED": "PARTIAL",
        "LABELED_OBSERVATION_CAPTURED": "PARTIAL",
        "VERSION_DOMAIN_CLASSIFIED": "PARTIAL",
        "BASELINE_LOCKED": "PROVEN",
    }
    for state, typed_state in expected_projection.items():
        row = projection.get(state)
        if not isinstance(row, dict) or row.get("typed_state") != typed_state:
            raise FirmwareProtocolError(f"presentation_showcase_projection_invalid:{state}")

    return payload


def _validate_site_profile(value: Any, catalog: dict[str, Any]) -> dict[str, Any] | None:
    if value is None:
        return None
    if not isinstance(value, dict):
        raise FirmwareProtocolError("site_profile_must_be_object_or_null")

    contract = catalog["site_profile_contract"]
    missing = [
        field for field in contract["required_fields"]
        if not isinstance(value.get(field), str) or not str(value.get(field)).strip()
    ]
    if missing:
        raise FirmwareProtocolError("site_profile_missing_fields:" + ",".join(sorted(missing)))

    if value["organization_id"] != contract["organization_id"]:
        raise FirmwareProtocolError("site_profile_wrong_organization")
    if value["scope_type"] not in contract["allowed_scope_types"]:
        raise FirmwareProtocolError("site_profile_scope_type_invalid")

    profile = {
        "profile_id": value["profile_id"].strip(),
        "organization_id": value["organization_id"],
        "scope_type": value["scope_type"],
        "status": value["status"],
        "profile_authority_ref": value["profile_authority_ref"].strip(),
        "site_id": None,
        "preference_order": _string_list(value.get("preference_order"), "site_profile.preference_order"),
        "disabled_protocols": _string_list(value.get("disabled_protocols"), "site_profile.disabled_protocols"),
    }
    if value.get("site_id") is not None:
        if not isinstance(value["site_id"], str) or not value["site_id"].strip():
            raise FirmwareProtocolError("site_profile_site_id_must_be_non_empty_string_or_null")
        profile["site_id"] = value["site_id"].strip()

    if profile["scope_type"] == "site_override" and profile["site_id"] is None:
        raise FirmwareProtocolError("site_override_requires_site_id")
    return profile


def _resolved_order(catalog: dict[str, Any], preference_order: list[str]) -> list[str]:
    known = set(catalog["protocols"])
    unknown = [protocol_id for protocol_id in preference_order if protocol_id not in known]
    if unknown:
        raise FirmwareProtocolError("unknown_protocol_in_preference_order:" + ",".join(unknown))
    resolved = list(preference_order)
    for protocol_id in catalog["default_preference_order"]:
        if protocol_id not in resolved:
            resolved.append(protocol_id)
    return resolved


def select_firmware_protocols(
    context: dict[str, Any],
    *,
    contract_path: Path = CONTRACT,
) -> dict[str, Any]:
    """Return an additive, evidence-ranked protocol selection receipt."""
    if not isinstance(context, dict):
        raise FirmwareProtocolError("selection_context_must_be_object")

    catalog = load_protocol_contract(contract_path)
    evidence_signals = set(_string_list(context.get("evidence_signals"), "evidence_signals"))
    authority_signals = set(_string_list(context.get("authority_signals"), "authority_signals"))
    proven_gates = set(_string_list(context.get("proven_gates"), "proven_gates"))
    site_profile = _validate_site_profile(context.get("site_profile"), catalog)

    preference_order = site_profile["preference_order"] if site_profile else []
    disabled_protocols = set(site_profile["disabled_protocols"] if site_profile else [])
    known = set(catalog["protocols"])
    unknown_disabled = sorted(disabled_protocols - known)
    if unknown_disabled:
        raise FirmwareProtocolError("unknown_disabled_protocol:" + ",".join(unknown_disabled))

    order = _resolved_order(catalog, preference_order)
    profile_proven = bool(
        site_profile
        and site_profile["status"] == catalog["site_profile_contract"]["proven_status"]
    )
    candidates: list[dict[str, Any]] = []

    for rank, protocol_id in enumerate(order, start=1):
        spec = catalog["protocols"][protocol_id]
        required_evidence = set(spec["required_evidence_any"])
        matched_evidence = sorted(required_evidence & evidence_signals)
        evidence_observed = bool(matched_evidence)
        disabled = protocol_id in disabled_protocols
        lab_only = spec["operational_tier"] == "LAB_ONLY"

        if disabled:
            observation_state = "DISABLED_BY_SITE_POLICY"
        elif lab_only and evidence_observed:
            observation_state = "LAB_ONLY_EVIDENCED"
        elif evidence_observed:
            observation_state = "EVIDENCED"
        else:
            observation_state = "UNOBSERVED"

        missing_authority = sorted(
            set(spec["required_authority_for_mutation"]) - authority_signals
        )
        missing_gates = sorted(set(spec["required_gates_for_mutation"]) - proven_gates)

        if disabled:
            mutation_readiness = "BLOCKED_SITE_POLICY"
        elif not evidence_observed:
            mutation_readiness = "BLOCKED_EVIDENCE"
        elif not profile_proven:
            mutation_readiness = "BLOCKED_SITE_PROFILE"
        elif lab_only and "CONTROLLED_LAB_TARGET" in missing_gates:
            mutation_readiness = "BLOCKED_LAB_BOUNDARY"
        elif missing_authority:
            mutation_readiness = "BLOCKED_AUTHORITY"
        elif missing_gates:
            mutation_readiness = "BLOCKED_GATES"
        else:
            mutation_readiness = "ELIGIBLE_FOR_SEPARATE_MUTATION_DECISION"

        candidates.append({
            "protocol_id": protocol_id,
            "label": spec["label"],
            "rank": rank,
            "control_plane": spec["control_plane"],
            "operational_tier": spec["operational_tier"],
            "observation_state": observation_state,
            "matched_evidence_signals": matched_evidence,
            "required_evidence_any": spec["required_evidence_any"],
            "mutation_readiness": mutation_readiness,
            "missing_authority_signals": missing_authority,
            "missing_gates": missing_gates,
            "observation_capabilities": spec["observation_capabilities"],
            "mutation_capabilities": spec["mutation_capabilities"],
            "presentation_role": spec["presentation_role"],
        })

    evidenced_production = [
        candidate for candidate in candidates
        if candidate["observation_state"] == "EVIDENCED"
    ]
    evidenced_lab = [
        candidate for candidate in candidates
        if candidate["observation_state"] == "LAB_ONLY_EVIDENCED"
    ]
    primary = evidenced_production[0]["protocol_id"] if evidenced_production else None
    if primary is not None:
        selection_state = "EVIDENCED_PROTOCOL_SELECTED"
    elif evidenced_lab:
        selection_state = "ONLY_LAB_PROTOCOL_EVIDENCED"
    else:
        selection_state = "NO_EVIDENCED_PROTOCOL"

    return {
        "schema": SCHEMA,
        "site_profile": site_profile,
        "site_profile_proven": profile_proven,
        "selection_state": selection_state,
        "primary_protocol": primary,
        "evidenced_fallback_protocols": [
            candidate["protocol_id"] for candidate in evidenced_production
            if candidate["protocol_id"] != primary
        ],
        "preserved_protocols": [candidate["protocol_id"] for candidate in candidates],
        "candidate_count": len(candidates),
        "candidates": candidates,
        "mutation_authorized": False,
        "proof_ceiling": catalog["proof_ceiling"],
    }


def dispatch_protocol_observation(
    selection: dict[str, Any],
    *,
    contract_path: Path = CONTRACT,
) -> dict[str, Any]:
    """Translate a selection receipt into one read-only observation route."""
    if not isinstance(selection, dict) or selection.get("schema") != SCHEMA:
        raise FirmwareProtocolError("valid_selection_receipt_required")
    if selection.get("mutation_authorized") is not False:
        raise FirmwareProtocolError("selection_receipt_must_deny_mutation")

    catalog = load_protocol_contract(contract_path)
    primary = selection.get("primary_protocol")
    if primary is None:
        return {
            "schema": DISPATCH_SCHEMA,
            "dispatch_state": "NO_PRODUCTION_PROTOCOL_SELECTED",
            "protocol_id": None,
            "mode": "READONLY_DISCOVERY",
            "front_door": None,
            "alternate_front_door": None,
            "next_action": "Collect additional site/device management-plane evidence; do not mutate the reader.",
            "mutation_authorized": False,
        }
    if primary not in catalog["protocols"]:
        raise FirmwareProtocolError("selection_primary_protocol_unknown")

    route = catalog["protocols"][primary]["observation_dispatch"]
    return {
        "schema": DISPATCH_SCHEMA,
        "dispatch_state": "READONLY_OBSERVATION_READY",
        "protocol_id": primary,
        "mode": route["mode"],
        "front_door": route.get("front_door"),
        "alternate_front_door": route.get("alternate_front_door"),
        "next_action": route["next_action"],
        "mutation_authorized": False,
    }


def select_and_dispatch(
    context: dict[str, Any],
    *,
    contract_path: Path = CONTRACT,
) -> dict[str, Any]:
    selection = select_firmware_protocols(context, contract_path=contract_path)
    dispatch = dispatch_protocol_observation(selection, contract_path=contract_path)
    return {"selection": selection, "dispatch": dispatch}


def _load_json_object(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise FirmwareProtocolError("input_root_must_be_object")
    return payload


def write_dispatch_receipt(
    payload: dict[str, Any],
    *,
    output_path: Path | None = None,
) -> Path:
    """Persist one ignored local read-only selection/dispatch receipt."""
    from datetime import datetime, timezone
    import secrets

    if output_path is None:
        DEFAULT_RECEIPT_DIR.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
        output_path = DEFAULT_RECEIPT_DIR / (
            f"hh-cc-reader-firmware-protocol-{stamp}-{secrets.token_hex(4)}.json"
        )
    else:
        output_path = output_path.expanduser().resolve()
        output_path.parent.mkdir(parents=True, exist_ok=True)

    receipt = {
        "schema": RECEIPT_SCHEMA,
        "mutation": "NONE",
        **payload,
    }
    output_path.write_text(
        json.dumps(receipt, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return output_path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("validate-contract")
    select = sub.add_parser("select")
    select.add_argument("--input", required=True, type=Path)
    dispatch = sub.add_parser("dispatch")
    dispatch.add_argument("--input", required=True, type=Path)
    dispatch.add_argument("--output", type=Path)

    args = parser.parse_args(argv)
    try:
        if args.command == "validate-contract":
            contract = load_protocol_contract()
            output = {
                "result": "PASS",
                "schema_version": contract["schema_version"],
                "protocol_count": len(contract["protocols"]),
            }
        else:
            payload = _load_json_object(args.input)
            if args.command == "select":
                output = select_firmware_protocols(payload)
            else:
                output = select_and_dispatch(payload)
                receipt_path = write_dispatch_receipt(output, output_path=args.output)
                output = {**output, "receipt_path": str(receipt_path)}
        print(json.dumps(output, indent=2, sort_keys=True))
        return 0
    except (OSError, json.JSONDecodeError, FirmwareProtocolError) as exc:
        print(json.dumps({"result": "FAIL", "error": str(exc)}, indent=2))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
