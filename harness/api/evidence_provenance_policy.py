"""Deterministic evidence-provenance and discriminator-satisfaction evaluator.

Answers two independent questions without conflating them:

1. Artifact provenance: where and when did the artifact actually come from?
2. Discriminator satisfaction: does the evidence already possessed answer the
   factual question?

A prior-run artifact stays PRIOR_RUN forever, while the same artifact may still
satisfy a current discriminator as SATISFIED_BY_PRIOR_PROVENANCE. Missing
same-run duplication alone never produces a restage requirement.

Local-only and dependency-free: no network access, no live evidence storage.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REGISTRY_PATH = ROOT / "harness" / "api" / "evidence-provenance-registry.json"

SATISFIED_STATES = frozenset({"SATISFIED_CURRENT_RUN", "SATISFIED_BY_PRIOR_PROVENANCE"})

_DEFAULTS: dict[str, Any] = {
    "artifact_run_id": None,
    "current_run_id": None,
    "artifact_provenance": None,
    "current_duplicate_present": False,
    "device_independent_discriminator": False,
    "identity_compatible": True,
    "question_compatible": True,
    "evidence_integrity_ok": True,
    "invalidation_reason": None,
    "freshness_class": "STABLE",
    "requires_fresh_observation": False,
    "freshness_satisfied": True,
    "requires_same_window": False,
    "same_window": False,
    "relevant_change_known_or_suspected": False,
    "conflicting_newer_evidence": False,
    "not_applicable": False,
    "operator_requested_reproduction": False,
}


def load_registry(path: Path = DEFAULT_REGISTRY_PATH) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    required = {
        "schema_version",
        "repository",
        "policy",
        "artifact_provenance_states",
        "discriminator_states",
        "freshness_classes",
        "reuse_conditions",
        "invalidation_reasons",
        "restage_rule",
        "allowed_restage_reasons",
        "bindings",
        "proof_ceiling",
    }
    missing = required - data.keys()
    assert not missing, f"registry missing fields: {sorted(missing)}"
    assert data["schema_version"] == "sas-evidence-provenance-registry/v1"
    return data


def _freshness_ids(registry: dict[str, Any]) -> set[str]:
    return {item["id"] for item in registry["freshness_classes"]}


def _result(
    artifact_run_id: Any,
    current_run_id: str,
    current_run_artifact_state: str,
    artifact_provenance: str,
    state: str,
    restage_required: bool,
    restage_allowed: bool,
    fail_closed: bool,
    reason: str | None,
) -> dict[str, Any]:
    return {
        "artifact_run_id": artifact_run_id,
        "current_run_id": current_run_id,
        "current_run_artifact_state": current_run_artifact_state,
        "artifact_provenance": artifact_provenance,
        "discriminator_state": state,
        "restage_required": restage_required,
        "restage_allowed": restage_allowed,
        "fail_closed": fail_closed,
        "reason": reason,
    }


def evaluate(inputs: dict[str, Any], registry: dict[str, Any] | None = None) -> dict[str, Any]:
    """Evaluate one discriminator against the two-axis provenance model.

    Raises ValueError for unknown states, unknown invalidation reasons, or
    freshness-class inputs that contradict each other; inconsistent input fails
    closed instead of silently producing a satisfied state.
    """
    registry = registry if registry is not None else load_registry()
    unknown = set(inputs) - set(_DEFAULTS)
    if unknown:
        raise ValueError(f"unknown provenance inputs: {sorted(unknown)}")
    data = {**_DEFAULTS, **inputs}

    artifact_states = set(registry["artifact_provenance_states"])
    freshness_ids = _freshness_ids(registry)
    invalidation_reasons = set(registry["invalidation_reasons"])

    current_run_id = data["current_run_id"]
    if current_run_id is None:
        raise ValueError("current_run_id is required")
    current_run_id = str(current_run_id)
    artifact_run_id = data["artifact_run_id"]
    if data["artifact_provenance"] is None:
        if artifact_run_id is None:
            raise ValueError("artifact_run_id is required when artifact_provenance is not given")
        artifact_provenance = (
            "CURRENT_RUN" if str(artifact_run_id) == current_run_id else "PRIOR_RUN"
        )
    else:
        artifact_provenance = str(data["artifact_provenance"])
    if artifact_provenance not in artifact_states:
        raise ValueError(f"unknown artifact provenance state: {artifact_provenance}")

    freshness_class = str(data["freshness_class"])
    if freshness_class not in freshness_ids:
        raise ValueError(f"unknown freshness class: {freshness_class}")
    if bool(data["requires_same_window"]) != (freshness_class == "WINDOW_COUPLED"):
        raise ValueError("requires_same_window must match the WINDOW_COUPLED freshness class")
    if bool(data["requires_fresh_observation"]) != (freshness_class == "VOLATILE"):
        raise ValueError("requires_fresh_observation must match the VOLATILE freshness class")

    invalidation_reason = data["invalidation_reason"]
    if invalidation_reason is not None:
        if invalidation_reason not in invalidation_reasons:
            raise ValueError(f"unknown invalidation reason: {invalidation_reason}")

    current_run_artifact_state = (
        "CURRENT_RUN" if bool(data["current_duplicate_present"]) else "MISSING"
    )

    def emit(
        state: str,
        restage_required: bool,
        restage_allowed: bool,
        fail_closed: bool,
        reason: str | None,
    ) -> dict[str, Any]:
        return _result(
            artifact_run_id,
            current_run_id,
            current_run_artifact_state,
            artifact_provenance,
            state,
            restage_required,
            restage_allowed,
            fail_closed,
            reason,
        )

    def satisfied(reason: str | None = None) -> dict[str, Any]:
        state = (
            "SATISFIED_BY_PRIOR_PROVENANCE"
            if artifact_provenance == "PRIOR_RUN"
            else "SATISFIED_CURRENT_RUN"
        )
        allow_restage = bool(data["operator_requested_reproduction"])
        if allow_restage and reason is None:
            reason = "OPERATOR_REQUESTED_REPRODUCTION"
        return emit(state, restage_required=False, restage_allowed=allow_restage, fail_closed=False, reason=reason)

    def restaged(state: str, reason: str, fail_closed: bool = False) -> dict[str, Any]:
        return emit(state, restage_required=True, restage_allowed=True, fail_closed=fail_closed, reason=reason)

    if bool(data["not_applicable"]):
        return emit("NOT_APPLICABLE", restage_required=False, restage_allowed=False, fail_closed=False, reason=None)

    if bool(data["conflicting_newer_evidence"]):
        return emit(
            "CONFLICT",
            restage_required=False,
            restage_allowed=True,
            fail_closed=True,
            reason="NEWER_EVIDENCE_CONFLICT",
        )

    if invalidation_reason == "OPERATOR_REQUESTED_REPRODUCTION":
        return satisfied(reason="OPERATOR_REQUESTED_REPRODUCTION")
    if invalidation_reason is not None:
        state = "CONFLICT" if invalidation_reason == "NEWER_EVIDENCE_CONFLICT" else "STALE_REVALIDATION_REQUIRED"
        return restaged(state, str(invalidation_reason), fail_closed=state == "CONFLICT")

    if artifact_provenance == "MISSING":
        return restaged("UNSATISFIED", "NO_ARTIFACT_AVAILABLE")
    if artifact_provenance in {"INVALID", "SUPERSEDED"}:
        return restaged("UNSATISFIED", "PRIOR_ARTIFACT_INVALID_OR_SUPERSEDED")

    if bool(data["relevant_change_known_or_suspected"]) and freshness_class in {
        "CONFIGURATION_SENSITIVE",
        "VOLATILE",
    }:
        return restaged("STALE_REVALIDATION_REQUIRED", "RELEVANT_STATE_CHANGE_SUSPECTED")

    identity_ok = bool(data["identity_compatible"]) or bool(data["device_independent_discriminator"])
    if not identity_ok:
        return restaged("UNSATISFIED", "READER_IDENTITY_INCOMPATIBLE")
    if not bool(data["question_compatible"]):
        return restaged("UNSATISFIED", "QUESTION_NOT_ANSWERED_BY_PRIOR_EVIDENCE")
    if not bool(data["evidence_integrity_ok"]):
        return restaged("UNSATISFIED", "PRIOR_EVIDENCE_INCOMPLETE")
    if bool(data["requires_same_window"]) and not bool(data["same_window"]):
        return restaged("UNSATISFIED", "SAME_WINDOW_TEMPORAL_COMPARISON_REQUIRED")
    if freshness_class == "VOLATILE" and not bool(data["freshness_satisfied"]):
        return restaged("STALE_REVALIDATION_REQUIRED", "FRESHNESS_POLICY_EXHAUSTED")

    return satisfied()
