#!/usr/bin/env python3
"""P95 additive firmware-protocol selector for H&H CC-reader work.

The selector ranks the next protocol to observe from site/device evidence while
preserving every configured protocol as a candidate. It never performs a live
mutation and never turns protocol selection into mutation authorization.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "harness/api/hh-cc-reader-firmware-protocols.v1.json"
SCHEMA = "sas-hh-cc-reader-firmware-protocol-selection/v1"


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
            "presentation_role",
        ):
            if field not in spec:
                raise FirmwareProtocolError(
                    f"protocol_field_missing:{protocol_id}:{field}"
                )
        _string_list(spec["observation_capabilities"], f"{protocol_id}.observation_capabilities")
        _string_list(spec["mutation_capabilities"], f"{protocol_id}.mutation_capabilities")
        evidence = _string_list(spec["required_evidence_any"], f"{protocol_id}.required_evidence_any")
        if not evidence:
            raise FirmwareProtocolError(f"protocol_evidence_signal_required:{protocol_id}")
        _string_list(
            spec["required_authority_for_mutation"],
            f"{protocol_id}.required_authority_for_mutation",
        )
        _string_list(
            spec["required_gates_for_mutation"],
            f"{protocol_id}.required_gates_for_mutation",
        )

    invariants = payload.get("invariants", {})
    for required_true in (
        "protocols_are_additive_not_mutually_destructive",
        "site_specific_preference_may_reorder_protocols",
        "unobserved_protocols_remain_preserved",
        "selection_never_authorizes_mutation",
        "lab_only_protocols_never_auto_select_for_production",
        "paxstore_is_default_fallback_not_global_default",
    ):
        if invariants.get(required_true) is not True:
            raise FirmwareProtocolError(f"required_invariant_missing:{required_true}")
    return payload


def _resolved_order(
    catalog: dict[str, Any],
    preference_order: list[str],
) -> list[str]:
    known = set(catalog["protocols"])
    unknown = [protocol_id for protocol_id in preference_order if protocol_id not in known]
    if unknown:
        raise FirmwareProtocolError(
            "unknown_protocol_in_preference_order:" + ",".join(unknown)
        )
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
    """Return an additive, evidence-ranked protocol selection receipt.

    Input keys:
      site_profile_id: optional sanitized identifier
      evidence_signals: observed technical/control-plane signals
      authority_signals: independently proven mutation-authority signals
      proven_gates: live execution gates already proven
      preference_order: optional site-specific ordering of known protocol IDs
      disabled_protocols: optional site-policy exclusions; excluded protocols
        remain present in the output rather than disappearing.

    The output always sets mutation_authorized=false.
    """
    if not isinstance(context, dict):
        raise FirmwareProtocolError("selection_context_must_be_object")

    catalog = load_protocol_contract(contract_path)
    evidence_signals = set(_string_list(context.get("evidence_signals"), "evidence_signals"))
    authority_signals = set(_string_list(context.get("authority_signals"), "authority_signals"))
    proven_gates = set(_string_list(context.get("proven_gates"), "proven_gates"))
    preference_order = _string_list(context.get("preference_order"), "preference_order")
    disabled_protocols = set(
        _string_list(context.get("disabled_protocols"), "disabled_protocols")
    )

    known = set(catalog["protocols"])
    unknown_disabled = sorted(disabled_protocols - known)
    if unknown_disabled:
        raise FirmwareProtocolError(
            "unknown_disabled_protocol:" + ",".join(unknown_disabled)
        )

    order = _resolved_order(catalog, preference_order)
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

        required_authority = set(spec["required_authority_for_mutation"])
        missing_authority = sorted(required_authority - authority_signals)
        required_gates = set(spec["required_gates_for_mutation"])
        missing_gates = sorted(required_gates - proven_gates)

        if disabled:
            mutation_readiness = "BLOCKED_SITE_POLICY"
        elif not evidence_observed:
            mutation_readiness = "BLOCKED_EVIDENCE"
        elif lab_only and "CONTROLLED_LAB_TARGET" in missing_gates:
            mutation_readiness = "BLOCKED_LAB_BOUNDARY"
        elif missing_authority:
            mutation_readiness = "BLOCKED_AUTHORITY"
        elif missing_gates:
            mutation_readiness = "BLOCKED_GATES"
        else:
            mutation_readiness = "ELIGIBLE_FOR_SEPARATE_MUTATION_DECISION"

        candidates.append(
            {
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
            }
        )

    evidenced_production = [
        candidate
        for candidate in candidates
        if candidate["observation_state"] == "EVIDENCED"
    ]
    evidenced_lab = [
        candidate
        for candidate in candidates
        if candidate["observation_state"] == "LAB_ONLY_EVIDENCED"
    ]

    primary = evidenced_production[0]["protocol_id"] if evidenced_production else None
    if primary is not None:
        selection_state = "EVIDENCED_PROTOCOL_SELECTED"
    elif evidenced_lab:
        selection_state = "ONLY_LAB_PROTOCOL_EVIDENCED"
    else:
        selection_state = "NO_EVIDENCED_PROTOCOL"

    evidenced_fallbacks = [
        candidate["protocol_id"]
        for candidate in evidenced_production
        if candidate["protocol_id"] != primary
    ]

    site_profile_id = context.get("site_profile_id")
    if site_profile_id is not None and (
        not isinstance(site_profile_id, str) or not site_profile_id.strip()
    ):
        raise FirmwareProtocolError("site_profile_id_must_be_non_empty_string_or_null")

    return {
        "schema": SCHEMA,
        "site_profile_id": site_profile_id.strip() if isinstance(site_profile_id, str) else None,
        "selection_state": selection_state,
        "primary_protocol": primary,
        "evidenced_fallback_protocols": evidenced_fallbacks,
        "preserved_protocols": [candidate["protocol_id"] for candidate in candidates],
        "candidate_count": len(candidates),
        "candidates": candidates,
        "mutation_authorized": False,
        "proof_ceiling": catalog["proof_ceiling"],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("validate-contract")
    select = sub.add_parser("select")
    select.add_argument("--input", required=True, type=Path)

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
            payload = json.loads(args.input.read_text(encoding="utf-8"))
            output = select_firmware_protocols(payload)
        print(json.dumps(output, indent=2, sort_keys=True))
        return 0
    except (OSError, json.JSONDecodeError, FirmwareProtocolError) as exc:
        print(json.dumps({"result": "FAIL", "error": str(exc)}, indent=2))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
