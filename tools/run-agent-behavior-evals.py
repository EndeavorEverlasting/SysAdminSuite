#!/usr/bin/env python3
"""Run deterministic, provider-agnostic SysAdminSuite agent behavior evals."""
from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
from typing import Any

RESULT_SCHEMA_VERSION = "sas-agent-behavior-eval-result/v1"
RESPONSE_SCHEMA_VERSION = "sas-agent-behavior-response-set/v1"
STRICT_DETERMINISTIC_SCORE = 1.0
STRICT_CRITICAL_FAILURES = 0
RESPONSE_TOP_LEVEL_KEYS = {"schema_version", "candidate_id", "responses"}
RESPONSE_ENTRY_KEYS = {"case_id", "classification", "remediation", "grounding_strategy", "actions", "tool_calls", "output_text", "judge", "human_review"}


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

    ledger = load_json(resolve_repo_path(repo_root, manifest["threshold_change_ledger"]))
    if ledger.get("schema_version") != "sas-agent-behavior-eval-threshold-approvals/v1" or ledger.get("suite_id") != manifest["suite_id"]:
        return False, None

    expected_from = {"deterministic_required_score": STRICT_DETERMINISTIC_SCORE, "critical_failures_allowed": STRICT_CRITICAL_FAILURES}
    expected_to = {"deterministic_required_score": score, "critical_failures_allowed": critical}
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


def _validate_tool_calls(value: Any, prefix: str, errors: list[str]) -> None:
    if not isinstance(value, list):
        errors.append(f"{prefix}.tool_calls_must_be_array")
        return
    for index, call in enumerate(value):
        if not isinstance(call, dict):
            errors.append(f"{prefix}.tool_calls[{index}]_must_be_object")
            continue
        if set(call) != {"name", "params"}:
            errors.append(f"{prefix}.tool_calls[{index}]_shape_mismatch")
        if not isinstance(call.get("name"), str) or not call.get("name", "").strip():
            errors.append(f"{prefix}.tool_calls[{index}].name_must_be_nonempty_string")
        if not isinstance(call.get("params"), dict):
            errors.append(f"{prefix}.tool_calls[{index}].params_must_be_object")


def load_response_set(path: Path) -> tuple[dict[str, Any], list[str]]:
    errors: list[str] = []
    try:
        payload = load_json(path)
    except (OSError, json.JSONDecodeError) as exc:
        return {"candidate_id": "<malformed-response-set>", "responses": []}, [f"response_set_unreadable: {exc}"]

    if not isinstance(payload, dict):
        return {"candidate_id": "<malformed-response-set>", "responses": []}, ["response_set_must_be_object"]
    extra_top = sorted(set(payload) - RESPONSE_TOP_LEVEL_KEYS)
    if extra_top:
        errors.append("response_set_unknown_properties: " + ",".join(extra_top))
    if payload.get("schema_version") != RESPONSE_SCHEMA_VERSION:
        errors.append(f"response_schema_version_mismatch: expected={RESPONSE_SCHEMA_VERSION!r} actual={payload.get('schema_version')!r}")

    candidate_id = payload.get("candidate_id")
    if not isinstance(candidate_id, str) or not candidate_id.strip():
        errors.append("candidate_id_must_be_nonempty_string")
        candidate_id = "<malformed-response-set>"

    raw_responses = payload.get("responses")
    if not isinstance(raw_responses, list):
        errors.append("responses_must_be_array")
        raw_responses = []

    responses: list[dict[str, Any]] = []
    for index, item in enumerate(raw_responses):
        prefix = f"response[{index}]"
        if not isinstance(item, dict):
            errors.append(f"{prefix}_must_be_object")
            continue
        extra_entry = sorted(set(item) - RESPONSE_ENTRY_KEYS)
        if extra_entry:
            errors.append(f"{prefix}_unknown_properties: " + ",".join(extra_entry))
        case_id = item.get("case_id")
        if not isinstance(case_id, str) or not case_id.strip():
            errors.append(f"{prefix}.case_id_must_be_nonempty_string")
            continue
        for field in ("classification", "remediation", "grounding_strategy"):
            if not isinstance(item.get(field), str) or not item[field].strip():
                errors.append(f"{prefix}.{field}_must_be_nonempty_string")
        actions = item.get("actions")
        if not isinstance(actions, list) or not all(isinstance(action, str) for action in actions):
            errors.append(f"{prefix}.actions_must_be_string_array")
        elif len(actions) != len(set(actions)):
            errors.append(f"{prefix}.actions_must_be_unique")
        _validate_tool_calls(item.get("tool_calls"), prefix, errors)
        if "output_text" in item and not isinstance(item.get("output_text"), str):
            errors.append(f"{prefix}.output_text_must_be_string")
        if "judge" in item:
            judge = item["judge"]
            if not isinstance(judge, dict) or set(judge) != {"rubric_version", "score"}:
                errors.append(f"{prefix}.judge_shape_mismatch")
        if "human_review" in item:
            review = item["human_review"]
            if not isinstance(review, dict) or set(review) != {"approved"} or not isinstance(review.get("approved"), bool):
                errors.append(f"{prefix}.human_review_shape_mismatch")
        responses.append(item)

    return {"schema_version": payload.get("schema_version"), "candidate_id": candidate_id, "responses": responses}, errors


def _patterns_match(patterns: list[str], output_text: str) -> tuple[bool, list[str]]:
    missing: list[str] = []
    for pattern in patterns:
        try:
            matched = re.search(pattern, output_text, flags=re.MULTILINE | re.DOTALL) is not None
        except re.error:
            matched = False
        if not matched:
            missing.append(pattern)
    return not missing, missing


def _forbidden_patterns_absent(patterns: list[str], output_text: str) -> tuple[bool, list[str]]:
    matched_patterns: list[str] = []
    for pattern in patterns:
        try:
            matched = re.search(pattern, output_text, flags=re.MULTILINE | re.DOTALL) is not None
        except re.error:
            matched = True
        if matched:
            matched_patterns.append(pattern)
    return not matched_patterns, matched_patterns


def score_case(case: dict[str, Any], response: dict[str, Any] | None) -> dict[str, Any]:
    oracle = case["oracle"]
    critical = bool(oracle.get("critical", False))
    criteria: list[dict[str, Any]] = []

    def check(name: str, passed: bool, expected: Any, actual: Any) -> None:
        criteria.append({"criterion": name, "passed": bool(passed), "expected": expected, "actual": actual})

    if response is None:
        check("response_present", False, "response for case", None)
        return {"case_id": case["id"], "failure_class": case["failure_class"], "layer": case["layer"], "critical": critical, "passed": False, "criteria": criteria, "risk": case.get("risk", {})}

    check("classification", response.get("classification") == oracle["classification"], oracle["classification"], response.get("classification"))
    check("remediation", response.get("remediation") == oracle["remediation"], oracle["remediation"], response.get("remediation"))
    check("grounding_strategy", response.get("grounding_strategy") == oracle["grounding_strategy"], oracle["grounding_strategy"], response.get("grounding_strategy"))

    raw_actions = response.get("actions")
    actions = [item for item in raw_actions if isinstance(item, str)] if isinstance(raw_actions, list) else []
    check("required_actions", subset(oracle.get("required_actions", []), actions), oracle.get("required_actions", []), actions)
    forbidden = sorted(set(oracle.get("forbidden_actions", [])) & set(actions))
    check("forbidden_actions_absent", not forbidden, [], forbidden)

    expected_calls = oracle.get("exact_tool_calls", [])
    actual_calls = response.get("tool_calls") if isinstance(response.get("tool_calls"), list) else []
    check("exact_tool_calls", canonical(actual_calls) == canonical(expected_calls), expected_calls, actual_calls)

    required_patterns = oracle.get("required_output_patterns", [])
    forbidden_patterns = oracle.get("forbidden_output_patterns", [])
    if required_patterns or forbidden_patterns:
        output_text = response.get("output_text") if isinstance(response.get("output_text"), str) else ""
        required_ok, missing_patterns = _patterns_match(required_patterns, output_text)
        forbidden_ok, matched_forbidden = _forbidden_patterns_absent(forbidden_patterns, output_text)
        check("required_output_patterns", required_ok, required_patterns, missing_patterns)
        check("forbidden_output_patterns_absent", forbidden_ok, [], matched_forbidden)

    mode = oracle.get("oracle_mode", "deterministic")
    if mode == "judge":
        judge = response.get("judge")
        required_version = oracle["judge_rubric_version"]
        threshold = float(oracle["judge_threshold"])
        score_value = judge.get("score") if isinstance(judge, dict) else None
        numeric_score = isinstance(score_value, (int, float)) and not isinstance(score_value, bool) and math.isfinite(float(score_value))
        judge_ok = isinstance(judge, dict) and judge.get("rubric_version") == required_version and numeric_score and float(score_value) >= threshold
        check("judge_threshold", judge_ok, {"rubric_version": required_version, "minimum_score": threshold}, judge)
    elif mode == "human":
        review = response.get("human_review")
        check("human_review", isinstance(review, dict) and review.get("approved") is True, {"approved": True}, review)

    return {"case_id": case["id"], "failure_class": case["failure_class"], "layer": case["layer"], "critical": critical, "passed": all(item["passed"] for item in criteria), "criteria": criteria, "risk": case.get("risk", {})}


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
    case_set = load_json(resolve_repo_path(repo_root, manifest["case_set"]))
    response_path = Path(args.responses)
    if not response_path.is_absolute():
        response_path = repo_root / response_path
    response_set, input_errors = load_response_set(response_path.resolve())

    cases = case_set["cases"]
    responses = response_set["responses"]
    response_by_id: dict[str, dict[str, Any]] = {}
    duplicate_response_ids = False
    for response in responses:
        case_id = response.get("case_id")
        if not isinstance(case_id, str) or not case_id:
            continue
        if case_id in response_by_id:
            duplicate_response_ids = True
            input_errors.append(f"duplicate_response_case_id: {case_id}")
        response_by_id[case_id] = response

    case_results = [score_case(case, response_by_id.get(case["id"])) for case in cases]
    known_case_ids = {case["id"] for case in cases}
    unknown_case_ids = sorted(set(response_by_id) - known_case_ids)
    if unknown_case_ids:
        input_errors.append("unknown_response_case_ids: " + ",".join(unknown_case_ids))

    passed_cases = sum(1 for item in case_results if item["passed"])
    total_cases = len(case_results)
    all_criteria = [criterion for item in case_results for criterion in item["criteria"]]
    passed_criteria = sum(1 for item in all_criteria if item["passed"])
    correctness_score = 0.0 if not all_criteria else passed_criteria / len(all_criteria)
    critical_failures = [item["case_id"] for item in case_results if item["critical"] and not item["passed"]]

    thresholds = manifest["thresholds"]
    threshold_relaxation_authorized, threshold_approval_id = threshold_authorization(manifest, repo_root)
    gate_pass = threshold_relaxation_authorized and not input_errors and not duplicate_response_ids and not unknown_case_ids and correctness_score >= float(thresholds["deterministic_required_score"]) and len(critical_failures) <= int(thresholds["critical_failures_allowed"])

    report = {
        "schema_version": RESULT_SCHEMA_VERSION,
        "suite_id": manifest["suite_id"],
        "manifest_version": manifest["schema_version"],
        "case_set_version": case_set["schema_version"],
        "response_schema_version": response_set.get("schema_version"),
        "candidate_id": response_set["candidate_id"],
        "gate_pass": gate_pass,
        "correctness_score": round(correctness_score, 6),
        "style_score": None,
        "threshold_relaxation_authorized": threshold_relaxation_authorized,
        "threshold_approval_id": threshold_approval_id,
        "passed_cases": passed_cases,
        "total_cases": total_cases,
        "critical_failures": critical_failures,
        "input_errors": input_errors,
        "unknown_response_case_ids": unknown_case_ids,
        "duplicate_response_ids": duplicate_response_ids,
        "case_results": case_results,
    }

    if args.report:
        report_path = Path(args.report)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    print(f"{response_set['candidate_id']}: {passed_cases}/{total_cases} cases; correctness={correctness_score:.3f}; critical_failures={len(critical_failures)}; input_errors={len(input_errors)}; threshold_authorized={threshold_relaxation_authorized}; gate={'PASS' if gate_pass else 'FAIL'}")
    if args.expect == "pass":
        return 0 if gate_pass else 1
    if args.expect == "fail":
        return 0 if not gate_pass else 1
    return 0 if gate_pass else 1


if __name__ == "__main__":
    raise SystemExit(main())
