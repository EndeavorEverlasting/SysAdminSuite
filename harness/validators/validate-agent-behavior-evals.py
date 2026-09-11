#!/usr/bin/env python3
"""Validate the versioned SysAdminSuite repository-wide AI behavior eval framework."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "harness/evals/agent-behavior-eval-manifest.v1.json"


def load_json(path: Path) -> dict:
    if not path.is_file():
        raise AssertionError(f"missing eval authority: {path.relative_to(ROOT)}")
    return json.loads(path.read_text(encoding="utf-8-sig"))


def resolve_repo_path(value: str) -> Path:
    path = ROOT / value
    if not path.resolve().is_relative_to(ROOT.resolve()):
        raise AssertionError(f"eval path escapes repository: {value}")
    return path


def run_candidate(manifest: dict, responses: Path, expect: str, report: Path) -> dict:
    runner = resolve_repo_path(manifest["runner"])
    completed = subprocess.run(
        [
            sys.executable,
            str(runner),
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
    if completed.returncode != 0:
        raise AssertionError(completed.stdout + "\n" + completed.stderr)
    return json.loads(report.read_text(encoding="utf-8"))


def main() -> int:
    manifest = load_json(MANIFEST)
    if manifest.get("schema_version") != "sas-agent-behavior-eval-manifest/v1":
        raise AssertionError("unexpected eval manifest schema version")

    authorities = {
        "schema": manifest["schema_path"],
        "cases": manifest["case_set"],
        "runner": manifest["runner"],
        "baseline": manifest["baseline_response_set"],
        "reference": manifest["reference_response_set"],
        "rubric": manifest["judge_rubric"],
    }
    resolved = {name: resolve_repo_path(path) for name, path in authorities.items()}
    for name, path in resolved.items():
        if not path.is_file():
            raise AssertionError(f"missing {name} eval authority: {path.relative_to(ROOT)}")

    schema = load_json(resolved["schema"])
    cases_doc = load_json(resolved["cases"])
    rubric = load_json(resolved["rubric"])
    baseline = load_json(resolved["baseline"])
    reference = load_json(resolved["reference"])

    if schema.get("$id") != manifest["schema_version"]:
        raise AssertionError("manifest/schema identity mismatch")

    layers = [item["layer"] for item in manifest["eval_pyramid"]]
    expected_layers = ["deterministic", "synthetic_integration", "model_judge", "human_review"]
    if layers != expected_layers:
        raise AssertionError(f"eval pyramid order mismatch: {layers}")
    if manifest["eval_pyramid"][0]["model_tokens_allowed"]:
        raise AssertionError("deterministic layer must not spend model tokens")
    if manifest["eval_pyramid"][1]["model_tokens_allowed"]:
        raise AssertionError("synthetic integration layer must not spend model tokens by default")
    if not manifest["eval_pyramid"][2]["model_tokens_allowed"]:
        raise AssertionError("model-judge layer must be the explicit model-token layer")

    thresholds = manifest["thresholds"]
    if thresholds["deterministic_required_score"] != 1.0:
        raise AssertionError("deterministic eval threshold must remain 1.0")
    if thresholds["critical_failures_allowed"] != 0:
        raise AssertionError("critical eval failures must remain fail-closed")
    if thresholds["baseline_must_fail"] is not True or thresholds["reference_candidate_must_pass"] is not True:
        raise AssertionError("baseline/reference polarity contract weakened")

    cases = cases_doc["cases"]
    case_ids = [case["id"] for case in cases]
    if len(case_ids) != len(set(case_ids)) or len(case_ids) < 10:
        raise AssertionError("eval case IDs must be unique and representative")
    if any(not case.get("risk", {}).get("false_positive") or not case.get("risk", {}).get("false_negative") for case in cases):
        raise AssertionError("every eval case must document false-positive and false-negative risk")

    paired = [case for case in cases if case.get("pair_id") == "grounding-context-pair"]
    if len(paired) != 2:
        raise AssertionError("grounding hallucination diagnosis must remain a paired eval")
    by_truth = {case["context"].get("truth_state"): case for case in paired}
    if set(by_truth) != {"absent", "present"}:
        raise AssertionError("grounding pair must contain truth absent and truth present cases")
    if by_truth["absent"]["oracle"]["grounding_strategy"] != "targeted_retrieval":
        raise AssertionError("missing truth must trigger targeted grounding")
    if by_truth["present"]["oracle"]["grounding_strategy"] != "reanchor_and_compact":
        raise AssertionError("present-but-ignored truth must trigger re-anchoring/compaction")
    if by_truth["present"]["oracle"]["exact_tool_calls"] != []:
        raise AssertionError("present-but-ignored truth must not trigger redundant retrieval")

    if rubric.get("correctness_and_style_are_separate") is not True:
        raise AssertionError("eval rubric must keep correctness separate from style")
    if "Do not invoke a model judge" not in rubric.get("activation_rule", ""):
        raise AssertionError("judge rubric must preserve deterministic-first token discipline")

    expected_case_ids = set(case_ids)
    if {item["case_id"] for item in baseline["responses"]} != expected_case_ids:
        raise AssertionError("known-failure baseline must cover the exact current case set")
    if {item["case_id"] for item in reference["responses"]} != expected_case_ids:
        raise AssertionError("reference candidate must cover the exact current case set")

    with tempfile.TemporaryDirectory(prefix="sas-agent-eval-validate-") as temp_dir:
        temp = Path(temp_dir)
        baseline_report = run_candidate(manifest, resolved["baseline"], "fail", temp / "baseline.json")
        candidate_report = run_candidate(manifest, resolved["reference"], "pass", temp / "candidate.json")

    if baseline_report["gate_pass"] is not False or not baseline_report["critical_failures"]:
        raise AssertionError("known-failure baseline was not rejected by the evaluator")
    if candidate_report["gate_pass"] is not True or candidate_report["correctness_score"] != 1.0:
        raise AssertionError("reference candidate did not satisfy the exact deterministic gate")
    if candidate_report["critical_failures"]:
        raise AssertionError("reference candidate contains critical eval failures")
    if candidate_report["correctness_score"] <= baseline_report["correctness_score"]:
        raise AssertionError("reference candidate does not improve on known-failure baseline")

    print("[PASS] repository AI eval authorities are present, versioned, and repository-contained")
    print("[PASS] eval pyramid is deterministic-first and model-judge use is explicitly gated")
    print("[PASS] paired hallucination diagnosis distinguishes absent truth from ignored present truth")
    print(
        "[PASS] baseline rejected: "
        f"score={baseline_report['correctness_score']:.6f}; "
        f"critical_failures={len(baseline_report['critical_failures'])}"
    )
    print(
        "[PASS] reference candidate accepted: "
        f"score={candidate_report['correctness_score']:.6f}; "
        f"cases={candidate_report['passed_cases']}/{candidate_report['total_cases']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
