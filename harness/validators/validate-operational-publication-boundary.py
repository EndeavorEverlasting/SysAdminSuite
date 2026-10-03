#!/usr/bin/env python3
"""Validate the reusable operational publication-boundary contract."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONTRACT = ROOT / "harness" / "api" / "operational-publication-boundary.v1.json"

EXPECTED_LIFECYCLE = [
    "WORKING",
    "CANDIDATE",
    "VALIDATED",
    "APPROVED_FOR_PUBLICATION",
    "PUBLISHED_UNVERIFIED",
    "PUBLISH_VERIFIED",
    "SUPERSEDED",
]


def _load(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("contract root must be an object")
    return payload


def validate_contract(payload: dict[str, Any]) -> list[str]:
    errors: list[str] = []

    if payload.get("schema_version") != "sas-operational-publication-boundary/v1":
        errors.append("schema_version")
    if payload.get("status") != "IMPLEMENTED":
        errors.append("status")

    principles = payload.get("principles")
    if not isinstance(principles, dict):
        errors.append("principles")
        principles = {}
    required_true = (
        "authority_projection_separation",
        "downstream_visibility_must_not_be_upstream_availability_dependency",
        "manual_publication_gate_is_first_class",
        "private_publication_manifest_is_allowed",
        "projection_receives_operational_contract_not_internal_implementation",
        "proof_must_flow_from_authority_to_projection",
        "projection_status_must_not_promote_authoritative_state",
    )
    for key in required_true:
        if principles.get(key) is not True:
            errors.append(f"principles.{key}")
    if principles.get("reverse_sync_default") != "DISABLED":
        errors.append("principles.reverse_sync_default")

    identity = payload.get("artifact_identity")
    if not isinstance(identity, dict):
        errors.append("artifact_identity")
        identity = {}
    for key in (
        "logical_artifact_key_is_provider_independent",
        "revision_is_separate_from_logical_identity",
        "provider_object_id_is_separate_from_logical_identity",
        "filename_is_not_identity",
        "hash_binds_a_specific_snapshot_not_the_logical_artifact",
    ):
        if identity.get(key) is not True:
            errors.append(f"artifact_identity.{key}")

    dimensions = payload.get("state_dimensions")
    if not isinstance(dimensions, dict) or dimensions.get("orthogonal") is not True:
        errors.append("state_dimensions.orthogonal")

    event = payload.get("event_contract")
    if not isinstance(event, dict):
        errors.append("event_contract")
        event = {}
    if event.get("idempotency_key") != "event_id":
        errors.append("event_contract.idempotency_key")
    required_event_fields = set(event.get("required_fields") or [])
    if not {"event_id", "logical_subject_key", "event_type", "occurred_at", "evidence_ref"} <= required_event_fields:
        errors.append("event_contract.required_fields")

    if payload.get("publication_lifecycle") != EXPECTED_LIFECYCLE:
        errors.append("publication_lifecycle")

    manifest = payload.get("publication_manifest_contract")
    if not isinstance(manifest, dict):
        errors.append("publication_manifest_contract")
        manifest = {}
    rules = manifest.get("rules") if isinstance(manifest.get("rules"), dict) else {}
    for key in (
        "logical_artifact_key_stable_across_revisions",
        "source_hash_required_for_validated_or_later",
        "validation_pass_required_before_approval",
        "manual_gate_may_promote_approved_to_published_unverified",
        "publish_verified_requires_independent_target_readback",
        "published_unverified_does_not_block_upstream_work",
        "target_provider_unavailable_is_not_source_failure",
    ):
        if rules.get(key) is not True:
            errors.append(f"publication_manifest_contract.rules.{key}")

    drift = payload.get("drift_rules")
    if not isinstance(drift, dict):
        errors.append("drift_rules")
        drift = {}
    if drift.get("downstream_change_is_input_evidence_not_automatic_writeback") is not True:
        errors.append("drift_rules.downstream_change_is_input_evidence_not_automatic_writeback")
    if drift.get("two_sided_divergence") != "CONFLICT":
        errors.append("drift_rules.two_sided_divergence")
    if drift.get("timestamp_newer_is_not_merge_authority") is not True:
        errors.append("drift_rules.timestamp_newer_is_not_merge_authority")

    return errors


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    path = Path(argv[0]).resolve() if argv else DEFAULT_CONTRACT
    try:
        payload = _load(path)
        errors = validate_contract(payload)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    if errors:
        print("FAIL: operational publication contract violations:")
        for item in errors:
            print(f"- {item}")
        return 1

    display = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
    print(f"PASS: {display}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
