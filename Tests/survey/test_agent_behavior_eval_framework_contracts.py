#!/usr/bin/env python3
"""Contracts for the repository-wide agent behavior eval framework."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "harness/evals/agent-behavior-eval-manifest.v1.json"
SCHEMA = ROOT / "schemas/harness/agent-behavior-eval-manifest.schema.json"
CASES = ROOT / "harness/evals/cases/repository-ai-core.v1.json"
RUBRIC = ROOT / "harness/evals/judges/repository-quality-rubric.v1.json"
WORKFLOW_SPEC = ROOT / "harness/workflows/agent-behavior-evals.yaml"
VALIDATOR = ROOT / "harness/validators/validate-agent-behavior-evals.py"
RUNNER = ROOT / "tools/run-agent-behavior-evals.py"
BASELINE = ROOT / "Tests/Fixtures/agent-evals/baseline-known-failures.v1.json"
REFERENCE = ROOT / "Tests/Fixtures/agent-evals/reference-candidate.v1.json"
WORKFLOW = ROOT / ".github/workflows/agent-behavior-evals.yml"
DOC = ROOT / "docs/AI_EVALS.md"


def load(path: Path) -> dict:
    assert path.is_file(), f"missing eval authority: {path.relative_to(ROOT)}"
    return json.loads(path.read_text(encoding="utf-8-sig"))


def run_eval(responses: Path, expect: str, report: Path) -> dict:
    completed = subprocess.run(
        [
            sys.executable,
            str(RUNNER),
            "--manifest",
            str(MANIFEST),
            "--responses",
            str(responses),
            "--expect",
            expect,
            "--report",
            str(report),
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stdout + "\n" + completed.stderr
    return json.loads(report.read_text(encoding="utf-8"))


def main() -> int:
    manifest = load(MANIFEST)
    schema = load(SCHEMA)
    cases_doc = load(CASES)
    rubric = load(RUBRIC)
    baseline = load(BASELINE)
    reference = load(REFERENCE)

    assert VALIDATOR.is_file(), "missing canonical AI eval validator"
    assert WORKFLOW_SPEC.is_file(), "missing harness-owned AI eval workflow spec"
    assert manifest["schema_version"] == "sas-agent-behavior-eval-manifest/v1"
    assert schema["$id"] == manifest["schema_version"]
    assert manifest["thresholds"]["deterministic_required_score"] == 1.0
    assert manifest["thresholds"]["critical_failures_allowed"] == 0
    assert manifest["thresholds"]["baseline_must_fail"] is True
    assert manifest["thresholds"]["reference_candidate_must_pass"] is True

    expected_layers = ["deterministic", "synthetic_integration", "model_judge", "human_review"]
    assert [item["layer"] for item in manifest["eval_pyramid"]] == expected_layers
    assert manifest["eval_pyramid"][0]["model_tokens_allowed"] is False
    assert manifest["eval_pyramid"][1]["model_tokens_allowed"] is False
    assert manifest["eval_pyramid"][2]["model_tokens_allowed"] is True

    cases = cases_doc["cases"]
    ids = [case["id"] for case in cases]
    assert len(ids) == len(set(ids)) and len(ids) >= 10
    assert all(case["risk"]["false_positive"] and case["risk"]["false_negative"] for case in cases)

    required_failure_classes = {
        "missing_context",
        "present_context_ignored",
        "tool_signature_mismatch",
        "missing_cmd_front_door",
        "malformed_tool_response",
        "incomplete_runtime_proof",
        "instruction_conflict",
        "authorization_missing",
        "schema_type_mismatch",
        "insufficient_identity_evidence",
        "repository_freshness_unproven",
    }
    assert required_failure_classes.issubset({case["failure_class"] for case in cases})

    paired = [case for case in cases if case.get("pair_id") == "grounding-context-pair"]
    assert len(paired) == 2
    by_truth = {case["context"]["truth_state"]: case for case in paired}
    assert set(by_truth) == {"absent", "present"}
    assert by_truth["absent"]["oracle"]["classification"] == "missing_context"
    assert by_truth["absent"]["oracle"]["grounding_strategy"] == "targeted_retrieval"
    assert by_truth["present"]["oracle"]["classification"] == "present_context_ignored"
    assert by_truth["present"]["oracle"]["grounding_strategy"] == "reanchor_and_compact"
    assert by_truth["present"]["oracle"]["exact_tool_calls"] == []

    signature_case = next(case for case in cases if case["id"] == "tool-signature.exact-operation-and-params")
    expected_call = signature_case["oracle"]["exact_tool_calls"][0]
    assert expected_call["params"]["operation_id"] == "agent_sprint_capsule.generate"
    assert expected_call["params"]["mode"] == "local_transform"

    cmd_case = next(case for case in cases if case["id"] == "field-guide.cmd-first.missing-launcher")
    assert "implement_cmd" in cmd_case["oracle"]["required_actions"]
    assert "emit_powershell_snippet_as_guide" in cmd_case["oracle"]["forbidden_actions"]
    assert "add_gui_before_cmd" in cmd_case["oracle"]["forbidden_actions"]

    assert rubric["correctness_and_style_are_separate"] is True
    assert "Do not invoke a model judge" in rubric["activation_rule"]

    response_case_ids = {item["case_id"] for item in reference["responses"]}
    assert response_case_ids == set(ids)
    assert {item["case_id"] for item in baseline["responses"]} == set(ids)

    with tempfile.TemporaryDirectory(prefix="sas-agent-evals-") as temp_dir:
        temp = Path(temp_dir)
        baseline_report = run_eval(BASELINE, "fail", temp / "baseline.json")
        candidate_report = run_eval(REFERENCE, "pass", temp / "candidate.json")

    assert baseline_report["gate_pass"] is False
    assert baseline_report["correctness_score"] < 1.0
    assert baseline_report["critical_failures"]
    assert candidate_report["gate_pass"] is True
    assert candidate_report["correctness_score"] == 1.0
    assert candidate_report["critical_failures"] == []
    assert candidate_report["style_score"] is None
    assert candidate_report["correctness_score"] > baseline_report["correctness_score"]

    workflow_spec_text = WORKFLOW_SPEC.read_text(encoding="utf-8-sig")
    for marker in (
        "operation_id: agent_behavior.eval",
        "mode: local_transform",
        "network_activity: false",
        "target_mutation: false",
        "validator: harness/validators/validate-agent-behavior-evals.py",
        "deterministic_correctness: 1.0",
        "critical_failures_allowed: 0",
    ):
        assert marker in workflow_spec_text, f"eval workflow spec missing marker: {marker}"

    workflow_text = WORKFLOW.read_text(encoding="utf-8-sig")
    for marker in (
        "python harness/validators/validate-agent-behavior-evals.py",
        "python Tests/survey/test_agent_behavior_eval_framework_contracts.py",
        "--expect fail",
        "--expect pass",
        "artifacts/ai-evals/baseline-result.json",
        "artifacts/ai-evals/reference-candidate-result.json",
        "actions/upload-artifact@v4",
    ):
        assert marker in workflow_text, f"eval CI missing marker: {marker}"

    doc_text = DOC.read_text(encoding="utf-8-sig")
    for marker in (
        "truth absent",
        "truth present but ignored",
        "Correctness is scored per criterion and per case",
        "Style is a separate field",
        "baseline fixture encodes known bad behaviors",
    ):
        assert marker in doc_text, f"eval documentation missing marker: {marker}"

    validator_run = subprocess.run(
        [sys.executable, str(VALIDATOR)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert validator_run.returncode == 0, validator_run.stdout + "\n" + validator_run.stderr

    print("[PASS] Agent eval manifest, schema, pyramid, rubric, workflow, and paths are versioned")
    print("[PASS] Grounding hallucination pair distinguishes absent truth from ignored present truth")
    print("[PASS] Exact operation IDs/tool parameters and CMD-first regressions are deterministic cases")
    print("[PASS] Known-failure baseline is rejected and reference candidate passes at score 1.0")
    print("[PASS] CI renders attributable baseline/candidate reports and preserves existing governance gates")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
