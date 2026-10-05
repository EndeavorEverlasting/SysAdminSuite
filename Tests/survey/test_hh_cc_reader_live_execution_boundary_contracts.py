#!/usr/bin/env python3
"""P95 recurrence contracts for the H&H CC-reader live-execution boundary."""
from __future__ import annotations

import hashlib
import json
import sys
import tempfile
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


def _evidence_file(tmp: str, gate: str = "BASELINE_LOCKED") -> tuple[str, str]:
    path = Path(tmp) / "gate-blocker.json"
    payload = {
        "schema": "test-gate-blocker/v1",
        "gate": gate,
        "classification": "VALID_EVIDENCE_REJECTED_BY_HARNESS",
    }
    path.write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return str(path), digest


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
    assert invariants["harness_preemption_requires_evidence_artifact_sha256_and_gate_binding"] is True
    assert invariants["after_harness_repair_resume_same_gate"] is True
    assert invariants["local_research_capability_gap_must_emit_successor_sprint"] is True
    assert invariants["research_capability_gap_is_not_terminal_blocker"] is True
    assert invariants["settled_protocol_selection_not_rerun_without_new_evidence"] is True
    assert invariants["current_gate_operator_path_must_match_latest_field_guide"] is True
    assert invariants["closed_local_discovery_cannot_reenter_current_next_action"] is True


def test_current_kiosk4_example_recovers_completed_observation_before_repeat() -> None:
    payload = json.loads(CONTRACT.read_text(encoding="utf-8"))
    example = payload["current_kiosk4_example"]
    action = example["next_action"]
    assert example["iteration_state"] == "LOCAL_CAPTURE_RECOVERED_EMPTY"
    assert example["local_recovery_state"] == "RECOVERED_EMPTY_STUB"
    assert example["capture_state_observed"] == "AWAITING_FIELD_OBSERVATION"
    assert example["labeled_observation_count"] == 0
    assert example["classifier_primary_bound"] is False
    assert example["baseline_receipt_state"] == "BASELINE_INCOMPLETE"
    assert example["baseline_missing_fields"] == ["current_firmware_value"]
    assert example["operator_reported_observation_complete"] is True
    assert example["evidence_ingested"] is False
    assert example["local_menu_state"] == "CLOSED"
    assert example["capture_classifier_state"] == "READY"
    assert example["version_domain_state"] == "VERSION_DOMAIN_UNRESOLVED"
    assert example["baseline_locked"] is False
    assert example["mutation_authorized"] is False
    assert "%TEMP%\\hh-cc-kiosk4-labeled-firmware-observation.json" in action
    assert "AWAITING_FIELD_OBSERVATION" in action
    assert "Classify-HHCCReaderVersionDomain.cmd" in action
    assert "Evaluate-HHCCReaderFirmwareRoundtrip.cmd baseline" in action
    assert "Fill the same private capture" in action
    assert "repeat the authorized read-only Kiosk4 observation merely because Git or Drive does not contain the private capture" in example["explicitly_not_next"]
    assert "promote operator-reported completion directly to current_firmware_value or BASELINE_LOCKED without classifier/baseline receipts" in example["explicitly_not_next"]
    assert "promote a PAXSTORE --fixture or credential_state=FIXTURE observe receipt as live current_firmware_value" in example["explicitly_not_next"]
    assert "invent current_firmware_value from campaign target 2.0.15.260522 or tracker history" in example["explicitly_not_next"]
    assert example["capture_template"].endswith("version-evidence-capture.template.json")

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


def test_confirmed_gate_blocking_harness_defect_requires_artifact_and_may_preempt() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        evidence_ref, digest = _evidence_file(tmp)
        result = route_work_item(
            {
                "current_gate": "BASELINE_LOCKED",
                "work_class": "CONFIRMED_HARNESS_DEFECT",
                "blocks_current_gate": True,
                "demonstrated_defect": True,
                "defect_evidence_ref": evidence_ref,
                "defect_evidence_sha256": digest,
                "defect_evidence_gate": "BASELINE_LOCKED",
            }
        )
    assert result["route"] == "HARNESS_REPAIR_THEN_RESUME"
    assert result["may_preempt_live_execution"] is True
    assert result["resume_gate"] == "BASELINE_LOCKED"


def test_plain_claim_cannot_preempt_without_artifact_proof() -> None:
    try:
        route_work_item(
            {
                "current_gate": "BASELINE_LOCKED",
                "work_class": "CONFIRMED_HARNESS_DEFECT",
                "blocks_current_gate": True,
                "demonstrated_defect": True,
                "defect_evidence_ref": "TEST:claimed-defect",
                "defect_evidence_sha256": "0" * 64,
                "defect_evidence_gate": "BASELINE_LOCKED",
            }
        )
        raise AssertionError("expected concrete evidence artifact requirement")
    except ExecutionBoundaryError as exc:
        assert "artifact_missing" in str(exc)


def test_wrong_gate_or_digest_cannot_preempt() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        evidence_ref, digest = _evidence_file(tmp)
        try:
            route_work_item(
                {
                    "current_gate": "BASELINE_LOCKED",
                    "work_class": "CONFIRMED_HARNESS_DEFECT",
                    "blocks_current_gate": True,
                    "demonstrated_defect": True,
                    "defect_evidence_ref": evidence_ref,
                    "defect_evidence_sha256": digest,
                    "defect_evidence_gate": "TARGET_UPDATE_PROVED",
                }
            )
            raise AssertionError("expected same-gate binding failure")
        except ExecutionBoundaryError as exc:
            assert "gate_must_match" in str(exc)

        try:
            route_work_item(
                {
                    "current_gate": "BASELINE_LOCKED",
                    "work_class": "CONFIRMED_HARNESS_DEFECT",
                    "blocks_current_gate": True,
                    "demonstrated_defect": True,
                    "defect_evidence_ref": evidence_ref,
                    "defect_evidence_sha256": "f" * 64,
                    "defect_evidence_gate": "BASELINE_LOCKED",
                }
            )
            raise AssertionError("expected digest mismatch")
        except ExecutionBoundaryError as exc:
            assert "sha256_mismatch" in str(exc)


def test_real_nonblocking_defect_is_deferred() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        evidence_ref, digest = _evidence_file(tmp)
        result = route_work_item(
            {
                "current_gate": "BASELINE_LOCKED",
                "work_class": "CONFIRMED_HARNESS_DEFECT",
                "blocks_current_gate": False,
                "demonstrated_defect": True,
                "defect_evidence_ref": evidence_ref,
                "defect_evidence_sha256": digest,
                "defect_evidence_gate": "BASELINE_LOCKED",
            }
        )
    assert result["route"] == "DEFER_HARNESS_MAINTENANCE"
    assert result["may_preempt_live_execution"] is False


def test_none_cannot_claim_to_block_current_gate() -> None:
    try:
        route_work_item(
            {
                "current_gate": "BASELINE_LOCKED",
                "work_class": "NONE",
                "blocks_current_gate": True,
            }
        )
        raise AssertionError("expected contradictory NONE blocker rejection")
    except ExecutionBoundaryError as exc:
        assert "none_work_class_cannot_block" in str(exc)


def test_nonblocking_side_lanes_cannot_claim_sas_gate_ownership() -> None:
    for work_class in ("NONBLOCKING_HARNESS_IMPROVEMENT", "DOWNSTREAM_PROJECT_OR_PUBLICATION"):
        try:
            route_work_item(
                {
                    "current_gate": "BASELINE_LOCKED",
                    "work_class": work_class,
                    "blocks_current_gate": True,
                }
            )
            raise AssertionError("expected nonblocking-class blocker rejection")
        except ExecutionBoundaryError as exc:
            assert "nonblocking_work_class_cannot_block" in str(exc)


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



def test_local_research_capability_gap_routes_to_successor_not_dead_end() -> None:
    result = route_work_item(
        {
            "current_gate": "PACKAGE_DOMAIN_BOUND",
            "work_class": "LOCAL_RESEARCH_CAPABILITY_GAP",
            "blocks_current_gate": True,
            "research_question": "Locate an authorized or provider-backed A80 firmware source for the target version domain.",
            "attempted_queries": ["exact target version", "A80 firmware target version"],
            "sources_attempted": ["public vendor support", "public manuals"],
            "exhausted_findings": ["no credible exact target package found on the public web"],
            "missing_capabilities": ["broader indexed web corpus", "authenticated partner/provider portal"],
            "unresolved_hypotheses": ["provider TMS catalog may carry the package", "authorized partner portal may expose the artifact"],
            "target_runtime": "frontier web-research runtime",
        }
    )
    assert result["route"] == "ESCALATE_RESEARCH_SUCCESSOR"
    assert result["successor_sprint_required"] is True
    assert result["may_preempt_live_execution"] is False
    assert result["resume_gate"] == "PACKAGE_DOMAIN_BOUND"
    assert "frontier web-research runtime" in result["next_action"]
    handoff = result["successor_handoff"]
    assert handoff["research_question"].startswith("Locate an authorized")
    assert handoff["attempted_queries"] == ["exact target version", "A80 firmware target version"]
    assert handoff["sources_attempted"] == ["public vendor support", "public manuals"]
    assert handoff["exhausted_findings"] == ["no credible exact target package found on the public web"]
    assert handoff["unresolved_hypotheses"] == ["provider TMS catalog may carry the package", "authorized partner portal may expose the artifact"]
    assert handoff["missing_capabilities"] == ["broader indexed web corpus", "authenticated partner/provider portal"]
    assert handoff["target_runtime"] == "frontier web-research runtime"
    assert handoff["resume_gate"] == "PACKAGE_DOMAIN_BOUND"


def test_research_successor_requires_exact_handoff_evidence() -> None:
    try:
        route_work_item(
            {
                "current_gate": "PACKAGE_DOMAIN_BOUND",
                "work_class": "LOCAL_RESEARCH_CAPABILITY_GAP",
                "blocks_current_gate": True,
                "research_question": "Find firmware.",
                "attempted_queries": [],
                "sources_attempted": ["public web"],
                "missing_capabilities": ["authenticated provider portal"],
                "target_runtime": "frontier web-research runtime",
            }
        )
        raise AssertionError("expected incomplete research handoff rejection")
    except ExecutionBoundaryError as exc:
        assert "research_capability_handoff_incomplete" in str(exc)


def test_research_successor_rejects_missing_hypothesis_field_and_non_strings() -> None:
    base = {
        "current_gate": "PACKAGE_DOMAIN_BOUND",
        "work_class": "LOCAL_RESEARCH_CAPABILITY_GAP",
        "blocks_current_gate": True,
        "research_question": "Find provider-backed package evidence.",
        "attempted_queries": ["query"],
        "sources_attempted": ["public web"],
        "exhausted_findings": [],
        "missing_capabilities": ["authenticated provider portal"],
        "target_runtime": "frontier web-research runtime",
    }
    try:
        route_work_item(base)
        raise AssertionError("expected missing unresolved_hypotheses rejection")
    except ExecutionBoundaryError as exc:
        assert "research_capability_handoff_incomplete" in str(exc)

    malformed = {
        **base,
        "unresolved_hypotheses": [],
        "attempted_queries": [1],
    }
    try:
        route_work_item(malformed)
        raise AssertionError("expected non-string query rejection")
    except ExecutionBoundaryError as exc:
        assert "research_capability_handoff_incomplete" in str(exc)

def test_docs_bind_p95_decision() -> None:
    boundary = BOUNDARY_DOC.read_text(encoding="utf-8")
    program = PROGRAM.read_text(encoding="utf-8")
    roundtrip = ROUNDTRIP.read_text(encoding="utf-8")
    for marker in (
        "live firmware execution is the primary program",
        "confirmed harness defect",
        "resume the same live gate",
        "BASELINE_LOCKED",
        "SHA-256",
    ):
        assert marker.casefold() in boundary.casefold()
    assert "P95 live-execution boundary" in program
    assert "P95 live-execution boundary" in roundtrip


def main() -> int:
    tests = [
        test_contract_shape_and_invariants,
        test_current_kiosk4_example_recovers_completed_observation_before_repeat,
        test_current_kiosk4_routes_to_live_runtime_not_harness,
        test_confirmed_gate_blocking_harness_defect_requires_artifact_and_may_preempt,
        test_plain_claim_cannot_preempt_without_artifact_proof,
        test_wrong_gate_or_digest_cannot_preempt,
        test_real_nonblocking_defect_is_deferred,
        test_none_cannot_claim_to_block_current_gate,
        test_nonblocking_side_lanes_cannot_claim_sas_gate_ownership,
        test_architecture_improvement_is_deferred,
        test_downstream_publication_is_deferred_and_cannot_block_sas,
        test_repository_staleness_refreshes_without_redesign,
        test_authority_gap_stops_mutation_without_inviting_harness_work,
        test_local_research_capability_gap_routes_to_successor_not_dead_end,
        test_research_successor_requires_exact_handoff_evidence,
        test_research_successor_rejects_missing_hypothesis_field_and_non_strings,
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
