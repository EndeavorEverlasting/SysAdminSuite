#!/usr/bin/env python3
"""Validate the versioned SysAdminSuite repository-wide AI behavior eval framework."""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "harness/evals/agent-behavior-eval-manifest.v1.json"


def load_json(path: Path) -> dict:
    if not path.is_file():
        raise AssertionError(f"missing eval authority: {path.relative_to(ROOT)}")
    return json.loads(path.read_text(encoding="utf-8-sig"))


def resolve_repo_path(value: str) -> Path:
    path = (ROOT / value).resolve()
    if not path.is_relative_to(ROOT.resolve()):
        raise AssertionError(f"eval path escapes repository: {value}")
    return path


def load_runner(path: Path):
    spec = importlib.util.spec_from_file_location("sas_agent_behavior_eval_runner", path)
    if spec is None or spec.loader is None:
        raise AssertionError("unable to import AI eval runner")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def validate_schema(instance: dict, schema: dict, label: str) -> None:
    Draft202012Validator.check_schema(schema)
    errors = sorted(Draft202012Validator(schema).iter_errors(instance), key=lambda item: list(item.path))
    if errors:
        details = "; ".join(f"{list(error.path)}: {error.message}" for error in errors[:8])
        raise AssertionError(f"{label} failed schema validation: {details}")


def run_candidate(manifest: dict, responses: Path, expect: str, report: Path) -> dict:
    runner = resolve_repo_path(manifest["runner"])
    completed = subprocess.run(
        [sys.executable, str(runner), "--manifest", str(MANIFEST), "--responses", str(responses), "--expect", expect, "--report", str(report)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        raise AssertionError(completed.stdout + "\n" + completed.stderr)
    return json.loads(report.read_text(encoding="utf-8"))


def main() -> int:
    manifest = load_json(MANIFEST)
    schema = load_json(resolve_repo_path(manifest["schema_path"]))
    validate_schema(manifest, schema, "AI eval manifest")
    if schema.get("$id") != manifest["schema_version"]:
        raise AssertionError("manifest/schema identity mismatch")

    authorities = {
        "response_schema": manifest["response_schema_path"],
        "cases": manifest["case_set"],
        "runner": manifest["runner"],
        "baseline": manifest["baseline_response_set"],
        "reference": manifest["reference_response_set"],
        "rubric": manifest["judge_rubric"],
        "threshold_ledger": manifest["threshold_change_ledger"],
    }
    resolved = {name: resolve_repo_path(path) for name, path in authorities.items()}
    for name, path in resolved.items():
        if not path.is_file():
            raise AssertionError(f"missing {name} eval authority: {path.relative_to(ROOT)}")

    response_schema = load_json(resolved["response_schema"])
    cases_doc = load_json(resolved["cases"])
    rubric = load_json(resolved["rubric"])
    threshold_ledger = load_json(resolved["threshold_ledger"])
    baseline = load_json(resolved["baseline"])
    reference = load_json(resolved["reference"])
    validate_schema(baseline, response_schema, "known-failure baseline response set")
    validate_schema(reference, response_schema, "reference candidate response set")

    if response_schema.get("$id") != "sas-agent-behavior-response-set/v1":
        raise AssertionError("unexpected response-set schema identity")
    if threshold_ledger.get("schema_version") != "sas-agent-behavior-eval-threshold-approvals/v1":
        raise AssertionError("unexpected threshold approval ledger version")
    if threshold_ledger.get("suite_id") != manifest["suite_id"] or not isinstance(threshold_ledger.get("records"), list):
        raise AssertionError("threshold approval ledger identity/shape mismatch")

    outcome_policy = manifest["outcome_policy"]
    for key in ("success", "acceptable_degradation", "failure"):
        if not outcome_policy.get(key):
            raise AssertionError(f"missing eval outcome policy: {key}")

    layers = [item["layer"] for item in manifest["eval_pyramid"]]
    if layers != ["deterministic", "synthetic_integration", "model_judge", "human_review"]:
        raise AssertionError(f"eval pyramid order mismatch: {layers}")

    thresholds = manifest["thresholds"]
    if thresholds["baseline_must_fail"] is not True or thresholds["reference_candidate_must_pass"] is not True:
        raise AssertionError("baseline/reference polarity contract weakened")
    runner_module = load_runner(resolved["runner"])
    threshold_ok, threshold_approval_id = runner_module.threshold_authorization(manifest, ROOT)
    if not threshold_ok:
        raise AssertionError("eval thresholds were relaxed without a matching approved evidence record")
    relaxed = (
        float(thresholds["deterministic_required_score"]) < runner_module.STRICT_DETERMINISTIC_SCORE
        or int(thresholds["critical_failures_allowed"]) > runner_module.STRICT_CRITICAL_FAILURES
    )
    if relaxed and not threshold_approval_id:
        raise AssertionError("relaxed eval thresholds are missing an approval ID")

    cases = cases_doc["cases"]
    case_ids = [case["id"] for case in cases]
    if len(case_ids) != len(set(case_ids)) or len(case_ids) < 10:
        raise AssertionError("eval case IDs must be unique and representative")
    if any(not case.get("risk", {}).get("false_positive") or not case.get("risk", {}).get("false_negative") for case in cases):
        raise AssertionError("every eval case must document false-positive and false-negative risk")

    paired = [case for case in cases if case.get("pair_id") == "grounding-context-pair"]
    by_truth = {case["context"].get("truth_state"): case for case in paired}
    if len(paired) != 2 or set(by_truth) != {"absent", "present"}:
        raise AssertionError("grounding pair must contain exactly truth absent and truth present")
    if by_truth["absent"]["oracle"]["grounding_strategy"] != "targeted_retrieval":
        raise AssertionError("missing truth must trigger targeted grounding")
    if by_truth["present"]["oracle"]["grounding_strategy"] != "reanchor_and_compact" or by_truth["present"]["oracle"]["exact_tool_calls"] != []:
        raise AssertionError("present-but-ignored truth must re-anchor without redundant retrieval")

    if rubric.get("correctness_and_style_are_separate") is not True or "Do not invoke a model judge" not in rubric.get("activation_rule", ""):
        raise AssertionError("judge rubric weakened deterministic-first scoring")

    expected_case_ids = set(case_ids)
    if {item["case_id"] for item in baseline["responses"]} != expected_case_ids:
        raise AssertionError("known-failure baseline must cover the exact current case set")
    if {item["case_id"] for item in reference["responses"]} != expected_case_ids:
        raise AssertionError("reference candidate must cover the exact current case set")

    with tempfile.TemporaryDirectory(prefix="sas-agent-eval-validate-") as temp_dir:
        temp = Path(temp_dir)
        baseline_report = run_candidate(manifest, resolved["baseline"], "fail", temp / "baseline.json")
        candidate_report = run_candidate(manifest, resolved["reference"], "pass", temp / "candidate.json")

    expected_baseline = manifest["baseline_expectation"]
    for key in ("passed_cases", "total_cases", "correctness_score", "critical_failures"):
        if baseline_report[key] != expected_baseline[key]:
            raise AssertionError(f"known-failure baseline drifted for {key}: expected={expected_baseline[key]!r} actual={baseline_report[key]!r}")
    if baseline_report["gate_pass"] is not False:
        raise AssertionError("known-failure baseline unexpectedly passed")
    if candidate_report["gate_pass"] is not True or candidate_report["correctness_score"] != 1.0 or candidate_report["critical_failures"]:
        raise AssertionError("reference candidate did not satisfy the exact deterministic gate")
    if candidate_report["threshold_relaxation_authorized"] is not True:
        raise AssertionError("current threshold contract was unexpectedly rejected")

    print("[PASS] AI eval manifest and response fixtures satisfy their Draft 2020-12 schemas")
    print("[PASS] repository AI eval authorities are versioned and repository-contained")
    print("[PASS] success, acceptable degradation, and failure criteria are explicit")
    print("[PASS] eval pyramid is deterministic-first and model-judge use is explicitly gated")
    print("[PASS] threshold relaxation requires a versioned approval/evidence ledger")
    print("[PASS] paired hallucination diagnosis distinguishes absent truth from ignored present truth")
    print(f"[PASS] baseline retained exact failures: score={baseline_report['correctness_score']:.6f}; critical={len(baseline_report['critical_failures'])}")
    print(f"[PASS] reference candidate accepted: score={candidate_report['correctness_score']:.6f}; cases={candidate_report['passed_cases']}/{candidate_report['total_cases']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
