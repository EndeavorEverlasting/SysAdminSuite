#!/usr/bin/env python3
"""P95 recurrence contracts for the H&H CC-reader live-execution boundary."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_live_execution_boundary import (  # noqa: E402
    ExecutionBoundaryError,
    route_work_item,
)

CONTRACT = ROOT / "harness/api/hh-cc-reader-live-execution-boundary.v1.json"
PROGRAM = ROOT / "docs/HH_CC_READER_REMOTE_OPERATIONS_PROGRAM.md"
ROUNDTRIP = ROOT / "docs/HH_CC_READER_FIRMWARE_ROUNDTRIP_BATCH_PLAN.md"
BOUNDARY_DOC = ROOT / "docs/HH_CC_READER_LIVE_EXECUTION_BOUNDARY.md"


def test_contract_shape_and_invariants() -> None:
    payload = json.loads(CONTRACT.read_text(encoding="utf-8"))
    assert payload["schema_version"] == "sas-hh-cc-reader-live-execution-boundary/v1"
    assert payload["status"] == "IMPLEMENTED"
    invariants = payload["invariants"]
    assert invariants["live_firmware_execution_is_primary"] is True
    assert invariants["nonblocking_harness_work_must_be_deferred"] is True
    assert invariants["external_access_or_missing_live_evidence_is_not_a_harness_defect"] is True
    assert invariants["downstream_tracker_or_publication_state_cannot_block_sas_execution"] is True
    assert invariants["confirmed_harness_defect_may_preempt_only_when_it_blocks_current_gate"] is True
    assert invariants["after_harness_repair_resume_same_gate"] is True


def test_current_kiosk4_routes_to_live_runtime_not_harness() -> None:
    result = route_work_item(
        {
            "current_gate": "BASELINE_LOCKED",
            "work_class": "EXTERNAL_ACCESS_OR_LIVE_EVIDENCE",
            "blocks_current_gate": True,
            "required_live_action": (
                "Authenticate to the estate surface and observe current firmware; "
                "otherwise capture Software versions on the same physical Kiosk4."
            ),
        }
    )
    assert result["route"] == "LIVE_RUNTIME_OR_OPERATOR_BOUNDARY"
    assert result["may_preempt_live_execution"] is False
    assert result["resume_gate"] == "BASELINE_LOCKED"
    assert "current firmware" in result["next_action"]


def test_confirmed_gate_blocking_harness_defect_may_preempt_then_resume() -> None:
    result = route_work_item(
        {
            "current_gate": "BASELINE_LOCKED",
            "work_class": "CONFIRMED_HARNESS_DEFECT",
            "blocks_current_gate": True,
            "demonstrated_defect": True,
            "defect_evidence_ref": "TEST:valid-live-firmware-rejected",
        }
    )
    assert result["route"] == "HARNESS_REPAIR_THEN_RESUME"
    assert result["may_preempt_live_execution"] is True
    assert result["resume_gate"] == "BASELINE_LOCKED"


def test_unproved_harness_defect_cannot_preempt() -> None:
    try:
        route_work_item(
            {
                "current_gate": "BASELINE_LOCKED",
                "work_class": "CONFIRMED_HARNESS_DEFECT",
                "blocks_current_gate": True,
                "demonstrated_defect": False,
                "defect_evidence_ref": "",
            }
        )
        raise AssertionError("expected fail-closed defect evidence requirement")
    except ExecutionBoundaryError as exc:
        assert "demonstrated_defect" in str(exc)


def test_real_nonblocking_defect_is_deferred() -> None:
    result = route_work_item(
        {
            "current_gate": "BASELINE_LOCKED",
            "work_class": "CONFIRMED_HARNESS_DEFECT",
            "blocks_current_gate": False,
            "demonstrated_defect": True,
            "defect_evidence_ref": "TEST:unrelated-renderer-bug",
        }
    )
    assert result["route"] == "DEFER_HARNESS_MAINTENANCE"
    assert result["may_preempt_live_execution"] is False


def test_architecture_improvement_is_deferred() -> None:
    result = route_work_item(
        {
            "current_gate": "BASELINE_LOCKED",
            "work_class": "NONBLOCKING_HARNESS_IMPROVEMENT",
            "blocks_current_gate": False,
        }
    )
    assert result["route"] == "DEFER_HARNESS_MAINTENANCE"


def test_downstream_publication_is_deferred_and_cannot_block_sas() -> None:
    result = route_work_item(
        {
            "current_gate": "BASELINE_LOCKED",
            "work_class": "DOWNSTREAM_PROJECT_OR_PUBLICATION",
            "blocks_current_gate": False,
        }
    )
    assert result["route"] == "DEFER_DOWNSTREAM_PROJECT_WORK"
    assert result["may_preempt_live_execution"] is False


def test_repository_staleness_refreshes_without_redesign() -> None:
    result = route_work_item(
        {
            "current_gate": "BASELINE_LOCKED",
            "work_class": "REPOSITORY_STALENESS",
            "blocks_current_gate": True,
        }
    )
    assert result["route"] == "REFRESH_RUNTIME_THEN_CONTINUE"
    assert result["resume_gate"] == "BASELINE_LOCKED"


def test_authority_gap_stops_mutation_without_inviting_harness_work() -> None:
    result = route_work_item(
        {
            "current_gate": "TARGET_UPDATE_PROVED",
            "work_class": "LIVE_AUTHORITY_OR_SAFETY_GAP",
            "blocks_current_gate": True,
        }
    )
    assert result["route"] == "STOP_MUTATION_RESOLVE_AUTHORITY"
    assert result["may_preempt_live_execution"] is False


def test_docs_bind_p95_decision() -> None:
    boundary = BOUNDARY_DOC.read_text(encoding="utf-8")
    program = PROGRAM.read_text(encoding="utf-8")
    roundtrip = ROUNDTRIP.read_text(encoding="utf-8")
    for marker in (
        "live firmware execution is the primary program",
        "confirmed harness defect",
        "resume the same live gate",
        "BASELINE_LOCKED",
    ):
        assert marker.casefold() in boundary.casefold()
    assert "P95 live-execution boundary" in program
    assert "P95 live-execution boundary" in roundtrip


def main() -> int:
    tests = [
        test_contract_shape_and_invariants,
        test_current_kiosk4_routes_to_live_runtime_not_harness,
        test_confirmed_gate_blocking_harness_defect_may_preempt_then_resume,
        test_unproved_harness_defect_cannot_preempt,
        test_real_nonblocking_defect_is_deferred,
        test_architecture_improvement_is_deferred,
        test_downstream_publication_is_deferred_and_cannot_block_sas,
        test_repository_staleness_refreshes_without_redesign,
        test_authority_gap_stops_mutation_without_inviting_harness_work,
        test_docs_bind_p95_decision,
    ]
    failed = 0
    for test in tests:
        try:
            test()
            print(f"PASS {test.__name__}")
        except Exception as exc:  # noqa: BLE001
            failed += 1
            print(f"FAIL {test.__name__}: {exc}")
    if failed:
        print(f"FAILED {failed}/{len(tests)}")
        return 1
    print(f"PASSED {len(tests)}/{len(tests)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
