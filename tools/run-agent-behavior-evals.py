#!/usr/bin/env python3
"""Run deterministic, provider-agnostic SysAdminSuite agent behavior evals."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

RESULT_SCHEMA_VERSION = "sas-agent-behavior-eval-result/v1"
STRICT_DETERMINISTIC_SCORE = 1.0
STRICT_CRITICAL_FAILURES = 0


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def subset(required: list[str], actual: list[str]) -> bool:
    return set(required).issubset(set(actual))


def resolve_repo_path(repo_root: Path, value: str) -> Path:
    path = (repo_root / value).resolve()
    if not path.is_relative_to(repo_root.resolve()):
        raise ValueError(f"eval path escapes repository: {value}")
    return path


def threshold_authorization(manifest: dict[str, Any], repo_root: Path) -> tuple[bool, str | None]:
    thresholds = manifest["thresholds"]
    score = float(thresholds["deterministic_required_score"])
    critical = int(thresholds["critical_failures_allowed"])
    relaxed = score < STRICT_DETERMINISTIC_SCORE or critical > STRICT_CRITICAL_FAILURES
    if not relaxed:
        return True, None

    ledger_path = resolve_repo_path(repo_root, manifest["threshold_change_ledger"])
    ledger = load_json(ledger_path)
    if ledger.get("schema_version") != "sas-agent-behavior-eval-threshold-approvals/v1":
        return False, None
    if ledger.get("suite_id") != manifest["suite_id"]:
        return False, None

    expected_from = {
        "deterministic_required_score": STRICT_DETERMINISTIC_SCORE,
        "critical_failures_allowed": STRICT_CRITICAL_FAILURES,
    }
    expected_to = {
        "deterministic_required_score": score,
        "critical_failures_allowed": critical,
    }
    for record in ledger.get("records", []):
        if not isinstance(record, dict) or record.get("approved") is not True:
            continue
        if record.get("from_thresholds") != expected_from or record.get("to_thresholds") != expected_to:
            continue
        if not all(isinstance(record.get(key), str) and record[key].strip() for key in ("approval_id", "approved_by_role", "approved_at", "rationale")):
            continue
        evidence_refs = record.get("evidence_refs")
        if not isinstance(evidence_refs, list) or not evidence_refs or not all(isinstance(item, str) and item.strip() for item in evidence_refs):
            continue
        return True, str(record["approval_id"])
    return False, None


def score_case(case: dict[str, Any], response: dict[str, Any] | None) -> dict[str, Any]:
    oracle = case["oracle"]
    critical = bool(oracle.get("critical", False))
    criteria: list[dict[str, Any]] = []

    def check(name: str, passed: bool, expected: Any, actual: Any) -> None:
        criteria.append({
            "criterion": name,
            "passed": bool(passed),
            "expected": expected,
            "actual": actual,
        })

    if response is None:
        check("response_present", False, "response for case", None)
        return {
            "case_id": case["id"],
            "failure_class": case["failure_class"],
            "layer": case["layer"],
            "critical": critical,
            "passed": False,
            "criteria": criteria,
            "risk": case.get("risk", {}),
        }

    check("classification", response.get("classification") == oracle["classification"], oracle["classification"], response.get("classification"))
    check("remediation", response.get("remediation") == oracle["remediation"], oracle["remediation"], response.get("remediation"))
    check("grounding_strategy", response.get("grounding_strategy") == oracle["grounding_strategy"], oracle["grounding_strategy"], response.get("grounding_strategy"))

    actions = response.get("actions")
    if not isinstance(actions, list):
        actions = []
    check("required_actions", subset(oracle.get("required_actions", []), actions), oracle.get("required_actions", []), actions)
    forbidden = sorted(set(oracle.get("forbidden_actions", [])) & set(actions))
    check("forbidden_actions_absent", not forbidden, [], forbidden)

    expected_calls = oracle.get("exact_tool_calls", [])
    actual_calls = response.get("tool_calls")
    if not isinstance(actual_calls, list):
        actual_calls = []
    check("exact_tool_calls", canonical(actual_calls) == canonical(expected_calls), expected_calls, actual_calls)

    mode = oracle.get("oracle_mode", "deterministic")
    if mode == "judge":
        judge = response.get("judge")
        required_version = oracle["judge_rubric_version"]
        threshold = float(oracle["judge_threshold"])
        judge_ok = (
            isinstance(judge, dict)
            and judge.get("rubric_version") == required_version
            and isinstance(judge.get("score"), (int, float))
            and float(judge["score"]) >= threshold
        )
        check("judge_threshold", judge_ok, {"rubric_version": required_version, "minimum_score": threshold}, judge)
    elif mode == "human":
        review = response.get("human_review")
        human_ok = isinstance(review, dict) and review.get("approved") is True
        check("human_review", human_ok, {"approved": True}, review)

    passed = all(item["passed"] for item in criteria)
    return {
        "case_id": case["id"],
        "failure_class": case["failure_class"],
        "layer": case["layer"],
        "critical": critical,
        "passed": passed,
        "criteria": criteria,
        "risk": case.get("risk", {}),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--responses", required=True)
    parser.add_argument("--expect", choices=("pass", "fail"))
    parser.add_argument("--report")
    args = parser.parse_args()

    manifest_path = Path(args.manifest).resolve()
    manifest = load_json(manifest_path)
    repo_root = manifest_path.parents[2]
    case_path = resolve_repo_path(repo_root, manifest["case_set"])
    response_path = Path(args.responses)
    if not response_path.is_absolute():
        response_path = repo_root / response_path
    response_path = response_path.resolve()

    case_set = load_json(case_path)
    response_set = load_json(response_path)
    cases = case_set["cases"]
    responses = response_set["responses"]
    response_by_id = {item["case_id"]: item for item in responses}
    duplicate_response_ids = len(response_by_id) != len(responses)

    case_results = [score_case(case, response_by_id.get(case["id"])) for case in cases]
    unknown_case_ids = sorted(set(response_by_id) - {case["id"] for case in cases})
    passed_cases = sum(1 for item in case_results if item["passed"])
    total_cases = len(case_results)
    all_criteria = [criterion for item in case_results for criterion in item["criteria"]]
    passed_criteria = sum(1 for item in all_criteria if item["passed"])
    total_criteria = len(all_criteria)
    correctness_score = 0.0 if total_criteria == 0 else passed_criteria / total_criteria
    critical_failures = [item["case_id"] for item in case_results if item["critical"] and not item["passed"]]

    thresholds = manifest["thresholds"]
    threshold_relaxation_authorized, threshold_approval_id = threshold_authorization(manifest, repo_root)
    gate_pass = (
        threshold_relaxation_authorized
        and not duplicate_response_ids
        and not unknown_case_ids
        and correctness_score >= float(thresholds["deterministic_required_score"])
        and len(critical_failures) <= int(thresholds["critical_failures_allowed"])
    )

    report = {
        "schema_version": RESULT_SCHEMA_VERSION,
        "suite_id": manifest["suite_id"],
        "manifest_version": manifest["schema_version"],
        "case_set_version": case_set["schema_version"],
        "candidate_id": response_set["candidate_id"],
        "gate_pass": gate_pass,
        "correctness_score": round(correctness_score, 6),
        "style_score": None,
        "threshold_relaxation_authorized": threshold_relaxation_authorized,
        "threshold_approval_id": threshold_approval_id,
        "passed_cases": passed_cases,
        "total_cases": total_cases,
        "critical_failures": critical_failures,
        "unknown_response_case_ids": unknown_case_ids,
        "duplicate_response_ids": duplicate_response_ids,
        "case_results": case_results,
    }

    if args.report:
        report_path = Path(args.report)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    print(
        f"{response_set['candidate_id']}: {passed_cases}/{total_cases} cases; "
        f"correctness={correctness_score:.3f}; critical_failures={len(critical_failures)}; "
        f"threshold_authorized={threshold_relaxation_authorized}; gate={'PASS' if gate_pass else 'FAIL'}"
    )

    if args.expect == "pass" and not gate_pass:
        return 1
    if args.expect == "fail" and gate_pass:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
