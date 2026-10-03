"""P95 live-execution boundary router for H&H CC-reader firmware work.

This module answers one narrow question: may a work item interrupt the live
firmware execution lane? It does not perform reader mutation, management-plane
access, tracker publication, or generic harness maintenance.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

SCHEMA = "sas-hh-cc-reader-live-execution-boundary/v1"

WORK_CLASSES = {
    "NONE",
    "EXTERNAL_ACCESS_OR_LIVE_EVIDENCE",
    "CONFIRMED_HARNESS_DEFECT",
    "NONBLOCKING_HARNESS_IMPROVEMENT",
    "DOWNSTREAM_PROJECT_OR_PUBLICATION",
    "REPOSITORY_STALENESS",
    "LIVE_AUTHORITY_OR_SAFETY_GAP",
}

ROUTES = {
    "CONTINUE_LIVE_EXECUTION",
    "LIVE_RUNTIME_OR_OPERATOR_BOUNDARY",
    "HARNESS_REPAIR_THEN_RESUME",
    "DEFER_HARNESS_MAINTENANCE",
    "DEFER_DOWNSTREAM_PROJECT_WORK",
    "REFRESH_RUNTIME_THEN_CONTINUE",
    "STOP_MUTATION_RESOLVE_AUTHORITY",
}


class ExecutionBoundaryError(ValueError):
    """Raised when routing input attempts to blur the execution boundary."""


@dataclass(frozen=True)
class ExecutionRoute:
    route: str
    may_preempt_live_execution: bool
    resume_gate: str
    next_action: str
    reason: str

    def as_dict(self) -> dict[str, Any]:
        return {
            "schema": SCHEMA,
            "route": self.route,
            "may_preempt_live_execution": self.may_preempt_live_execution,
            "resume_gate": self.resume_gate,
            "next_action": self.next_action,
            "reason": self.reason,
        }


def _text(value: Any) -> str:
    return str(value or "").strip()


def route_work_item(item: dict[str, Any]) -> dict[str, Any]:
    """Classify one proposed interruption of the live firmware lane.

    Required:
      current_gate
      work_class
      blocks_current_gate

    CONFIRMED_HARNESS_DEFECT additionally requires demonstrated_defect=True and
    a non-empty defect_evidence_ref. A missing credential, live observation,
    physical interaction, downstream publication problem, or architecture idea
    cannot be upgraded into a harness defect.
    """
    if not isinstance(item, dict):
        raise ExecutionBoundaryError("work_item_must_be_object")

    current_gate = _text(item.get("current_gate"))
    if not current_gate:
        raise ExecutionBoundaryError("current_gate_required")

    work_class = _text(item.get("work_class"))
    if work_class not in WORK_CLASSES:
        raise ExecutionBoundaryError("unsupported_work_class")

    blocks = item.get("blocks_current_gate")
    if not isinstance(blocks, bool):
        raise ExecutionBoundaryError("blocks_current_gate_must_be_boolean")

    if work_class == "CONFIRMED_HARNESS_DEFECT":
        if item.get("demonstrated_defect") is not True:
            raise ExecutionBoundaryError("confirmed_harness_defect_requires_demonstrated_defect")
        evidence_ref = _text(item.get("defect_evidence_ref"))
        if not evidence_ref:
            raise ExecutionBoundaryError("confirmed_harness_defect_requires_evidence_ref")
        if not blocks:
            return ExecutionRoute(
                "DEFER_HARNESS_MAINTENANCE",
                False,
                current_gate,
                "Record the defect for the harness-maintenance lane and continue live firmware execution.",
                "The defect is real but does not block the current live gate.",
            ).as_dict()
        return ExecutionRoute(
            "HARNESS_REPAIR_THEN_RESUME",
            True,
            current_gate,
            "Repair only the demonstrated blocker, validate the narrow gate, then resume the same live gate.",
            f"Confirmed harness defect blocks {current_gate}; evidence={evidence_ref}.",
        ).as_dict()

    if work_class == "EXTERNAL_ACCESS_OR_LIVE_EVIDENCE":
        return ExecutionRoute(
            "LIVE_RUNTIME_OR_OPERATOR_BOUNDARY",
            False,
            current_gate,
            _text(item.get("required_live_action"))
            or "Obtain the required authorized live observation/access and rerun the same gate.",
            "Missing live evidence or access is an operational boundary, not a harness defect.",
        ).as_dict()

    if work_class == "NONBLOCKING_HARNESS_IMPROVEMENT":
        return ExecutionRoute(
            "DEFER_HARNESS_MAINTENANCE",
            False,
            current_gate,
            "Record a bounded successor handoff and continue the live firmware gate.",
            "Architecture or harness improvement is non-blocking.",
        ).as_dict()

    if work_class == "DOWNSTREAM_PROJECT_OR_PUBLICATION":
        return ExecutionRoute(
            "DEFER_DOWNSTREAM_PROJECT_WORK",
            False,
            current_gate,
            "Route project/tracker/publication work downstream and continue SAS execution independently.",
            "Downstream visibility is not an upstream availability dependency.",
        ).as_dict()

    if work_class == "REPOSITORY_STALENESS":
        return ExecutionRoute(
            "REFRESH_RUNTIME_THEN_CONTINUE",
            False,
            current_gate,
            "Refresh provider/worktree truth without redesigning the program, then resume the same gate.",
            "Runtime freshness is required, but it does not authorize a harness redesign.",
        ).as_dict()

    if work_class == "LIVE_AUTHORITY_OR_SAFETY_GAP":
        return ExecutionRoute(
            "STOP_MUTATION_RESOLVE_AUTHORITY",
            False,
            current_gate,
            "Resolve the live authority/safety condition before mutation; preserve all prior proved gates.",
            "Mutation authority or safety is unresolved.",
        ).as_dict()

    return ExecutionRoute(
        "CONTINUE_LIVE_EXECUTION",
        False,
        current_gate,
        "Continue the current live firmware gate.",
        "No blocking side-lane condition is present.",
    ).as_dict()
