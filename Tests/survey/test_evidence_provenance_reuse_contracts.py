#!/usr/bin/env python3
"""Contracts for evidence-provenance reuse and the no-restage gate.

These fixtures encode the recurrence defect: a new RUN_ID lacks its own
START_TEST artifact while valid prior evidence already answers the factual
discriminator. The contract must keep those two truths separate instead of
converting the bookkeeping gap into repeated operator work.
"""
from __future__ import annotations

import ipaddress
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.evidence_provenance_policy import evaluate, load_registry

REGISTRY = ROOT / "harness/api/evidence-provenance-registry.json"
SCHEMA = ROOT / "schemas/harness/evidence-provenance-registry.schema.json"
POLICY = ROOT / "harness/api/evidence_provenance_policy.py"
VALIDATOR = ROOT / "harness/validators/validate-evidence-provenance-contracts.py"
HH_DOC = ROOT / "docs/HH_CC_READER_NETSTAT_BASELINE.md"
FIELD_SKILL = ROOT / ".claude/skills/field-workflow/SKILL.md"
HH_TEST = ROOT / "Tests/survey/test_hh_cc_reader_field_probe_contracts.py"
VALIDATORS = ROOT / "harness/api/harness-validator-registry.json"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"
OFFLINE = ROOT / "tests/survey/run_offline_survey_tests.sh"
CI = ROOT / ".github/workflows/evidence-provenance-contracts.yml"

PROVIDER_MARKERS = (
    "drive" + ".google.com",
    "docs" + ".google.com",
    "Google" + " Drive",
    "One" + "Drive",
    "Drop" + "box",
)
NETWORK_IMPORT = re.compile(
    r"(?m)^\s*(?:import|from)\s+(?:urllib|socket|requests|http|asyncio|ftplib|telnetlib)\b"
)


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def satisfied_baseline(**overrides) -> dict:
    inputs = {
        "artifact_run_id": "OLD_RUN",
        "current_run_id": "NEW_RUN",
        "current_duplicate_present": False,
        "identity_compatible": True,
        "question_compatible": True,
        "evidence_integrity_ok": True,
        "invalidation_reason": None,
        "freshness_class": "STABLE",
        "conflicting_newer_evidence": False,
    }
    inputs.update(overrides)
    return inputs


# Table-driven recurrence fixtures: each case names the exact inputs and the
# exact two-axis result the contract must produce.
CASES: list[tuple[str, dict, dict]] = [
    (
        "case1_recurrence_defect",
        satisfied_baseline(),
        {
            "artifact_provenance": "PRIOR_RUN",
            "discriminator_state": "SATISFIED_BY_PRIOR_PROVENANCE",
            "current_run_artifact_state": "MISSING",
            "restage_required": False,
            "restage_allowed": False,
            "fail_closed": False,
            "reason": None,
        },
    ),
    (
        "case2_missing_artifact_alone",
        satisfied_baseline(current_duplicate_present=False),
        {
            "discriminator_state": "SATISFIED_BY_PRIOR_PROVENANCE",
            "restage_required": False,
        },
    ),
    (
        "case3_firmware_changed",
        satisfied_baseline(invalidation_reason="RELEVANT_SOFTWARE_STATE_CHANGED"),
        {
            "discriminator_state": "STALE_REVALIDATION_REQUIRED",
            "restage_required": True,
            "restage_allowed": True,
            "reason": "RELEVANT_SOFTWARE_STATE_CHANGED",
        },
    ),
    (
        "case4_different_reader",
        satisfied_baseline(identity_compatible=False),
        {
            "artifact_provenance": "PRIOR_RUN",
            "discriminator_state": "UNSATISFIED",
            "restage_required": True,
            "restage_allowed": True,
            "reason": "READER_IDENTITY_INCOMPATIBLE",
        },
    ),
    (
        "case5_conflicting_newer_evidence",
        satisfied_baseline(conflicting_newer_evidence=True),
        {
            "discriminator_state": "CONFLICT",
            "fail_closed": True,
            "restage_allowed": True,
            "reason": "NEWER_EVIDENCE_CONFLICT",
        },
    ),
    (
        "case6_cross_window_delta",
        satisfied_baseline(
            artifact_run_id="RUN_A",
            current_run_id="RUN_B",
            freshness_class="WINDOW_COUPLED",
            requires_same_window=True,
            same_window=False,
        ),
        {
            "artifact_provenance": "PRIOR_RUN",
            "discriminator_state": "UNSATISFIED",
            "restage_required": True,
            "reason": "SAME_WINDOW_TEMPORAL_COMPARISON_REQUIRED",
        },
    ),
    (
        "case7_prior_completed_experiment",
        satisfied_baseline(current_duplicate_present=False, freshness_class="CONFIGURATION_SENSITIVE"),
        {
            "current_run_artifact_state": "MISSING",
            "discriminator_state": "SATISFIED_BY_PRIOR_PROVENANCE",
            "restage_required": False,
        },
    ),
]


def test_registry_and_schema_floor() -> None:
    registry = load(REGISTRY)
    schema = load(SCHEMA)
    assert registry["schema_version"] == "sas-evidence-provenance-registry/v1"
    assert registry["repository"] == "EndeavorEverlasting/SysAdminSuite"
    assert schema["$schema"].endswith("draft/2020-12/schema")
    assert schema["properties"]["schema_version"]["const"] == registry["schema_version"]
    assert all(value is True for value in registry["policy"].values()), (
        "provenance policy must keep every rule enabled"
    )
    for key in (
        "preserve_original_run_identity",
        "prior_provenance_may_satisfy_discriminator",
        "missing_current_duplicate_is_not_invalidation",
        "conflicts_require_resolution",
        "no_restage_without_invalidation_reason",
        "live_evidence_remains_untracked",
    ):
        assert key in registry["policy"], f"registry policy missing: {key}"
    assert registry["restage_rule"]["missing_same_run_duplication_is_not_by_itself_a_reason_to_repeat_operator_work"] is True
    assert registry["restage_rule"]["restage_requires_recorded_invalidation_reason"] is True
    try:
        import jsonschema  # type: ignore
    except ImportError:
        pass
    else:
        jsonschema.Draft202012Validator(schema).validate(registry)


def test_canonical_state_sets() -> None:
    registry = load_registry()
    assert registry["artifact_provenance_states"] == [
        "CURRENT_RUN",
        "PRIOR_RUN",
        "MISSING",
        "INVALID",
        "SUPERSEDED",
    ]
    assert registry["discriminator_states"] == [
        "SATISFIED_CURRENT_RUN",
        "SATISFIED_BY_PRIOR_PROVENANCE",
        "UNSATISFIED",
        "STALE_REVALIDATION_REQUIRED",
        "CONFLICT",
        "NOT_APPLICABLE",
    ]
    freshness = {item["id"] for item in registry["freshness_classes"]}
    assert freshness == {"STABLE", "CONFIGURATION_SENSITIVE", "VOLATILE", "WINDOW_COUPLED"}
    assert len(registry["reuse_conditions"]) == 6
    assert "READER_IDENTITY_INCOMPATIBLE" in registry["invalidation_reasons"]
    assert "RELEVANT_SOFTWARE_STATE_CHANGED" in registry["invalidation_reasons"]
    assert "OPERATOR_REQUESTED_REPRODUCTION" in registry["invalidation_reasons"]


def test_two_axis_recurrence_cases() -> None:
    for name, inputs, expected in CASES:
        result = evaluate(dict(inputs))
        for field, value in expected.items():
            assert result[field] == value, (
                f"{name}: {field}={result[field]!r}, expected {value!r} (result={result})"
            )


def test_missing_current_duplicate_never_forces_restage() -> None:
    with_dup = evaluate(satisfied_baseline(current_duplicate_present=True))
    without_dup = evaluate(satisfied_baseline(current_duplicate_present=False))
    assert with_dup["discriminator_state"] == without_dup["discriminator_state"]
    assert without_dup["restage_required"] is False
    assert without_dup["discriminator_state"] != "STALE_REVALIDATION_REQUIRED"
    assert without_dup["current_run_artifact_state"] == "MISSING"


def test_prior_run_is_never_relabelled_current() -> None:
    result = evaluate(satisfied_baseline())
    assert result["artifact_run_id"] == "OLD_RUN"
    assert result["current_run_id"] == "NEW_RUN"
    assert result["artifact_provenance"] == "PRIOR_RUN"


def test_explicit_invalidation_admits_revalidation() -> None:
    for reason in (
        "READER_IDENTITY_INCOMPATIBLE",
        "RELEVANT_SOFTWARE_STATE_CHANGED",
        "PRIOR_EVIDENCE_INCOMPLETE",
        "NEWER_EVIDENCE_CONFLICT",
        "FRESHNESS_POLICY_EXHAUSTED",
        "SAME_WINDOW_TEMPORAL_COMPARISON_REQUIRED",
    ):
        result = evaluate(satisfied_baseline(invalidation_reason=reason))
        assert result["restage_allowed"] is True, f"revalidation blocked for {reason}: {result}"
        assert result["restage_required"] is True
        assert result["discriminator_state"] in {"STALE_REVALIDATION_REQUIRED", "CONFLICT"}


def test_operator_reproduction_request_is_allowed_but_not_required() -> None:
    result = evaluate(satisfied_baseline(operator_requested_reproduction=True))
    assert result["discriminator_state"] == "SATISFIED_BY_PRIOR_PROVENANCE"
    assert result["restage_required"] is False
    assert result["restage_allowed"] is True
    assert result["reason"] == "OPERATOR_REQUESTED_REPRODUCTION"


def test_window_coupled_requires_same_window_evidence() -> None:
    cross = evaluate(
        satisfied_baseline(
            artifact_run_id="RUN_A",
            current_run_id="RUN_B",
            freshness_class="WINDOW_COUPLED",
            requires_same_window=True,
            same_window=False,
        )
    )
    assert cross["discriminator_state"] not in {
        "SATISFIED_CURRENT_RUN",
        "SATISFIED_BY_PRIOR_PROVENANCE",
    }
    same = evaluate(
        satisfied_baseline(
            artifact_run_id="OLD_RUN",
            current_run_id="OLD_RUN",
            current_duplicate_present=True,
            freshness_class="WINDOW_COUPLED",
            requires_same_window=True,
            same_window=True,
        )
    )
    assert same["discriminator_state"] == "SATISFIED_CURRENT_RUN"


def test_volatile_freshness_bounds_reuse() -> None:
    stale = evaluate(
        satisfied_baseline(freshness_class="VOLATILE", requires_fresh_observation=True, freshness_satisfied=False)
    )
    assert stale["discriminator_state"] == "STALE_REVALIDATION_REQUIRED"
    assert stale["restage_required"] is True
    assert stale["reason"] == "FRESHNESS_POLICY_EXHAUSTED"
    fresh = evaluate(
        satisfied_baseline(freshness_class="VOLATILE", requires_fresh_observation=True, freshness_satisfied=True)
    )
    assert fresh["discriminator_state"] == "SATISFIED_BY_PRIOR_PROVENANCE"
    assert fresh["restage_required"] is False


def test_inconsistent_freshness_inputs_fail_closed() -> None:
    for bad in (
        {"freshness_class": "WINDOW_COUPLED", "requires_same_window": False},
        {"freshness_class": "STABLE", "requires_same_window": True},
        {"freshness_class": "VOLATILE", "requires_fresh_observation": False},
        {"freshness_class": "STABLE", "requires_fresh_observation": True},
        {"freshness_class": "MADE_UP_CLASS"},
        {"invalidation_reason": "INVENTED_REASON"},
    ):
        try:
            evaluate(satisfied_baseline(**bad))
        except ValueError:
            continue
        raise AssertionError(f"inconsistent inputs did not fail closed: {bad}")


def test_hh_binding_carries_the_no_restage_rule() -> None:
    doc = read(HH_DOC)
    assert "## Prior-provenance satisfaction and no-restage rule" in doc
    for marker in (
        "SATISFIED_BY_PRIOR_PROVENANCE",
        "ARTIFACT_PROVENANCE",
        "DISCRIMINATOR_STATE",
        "RESTAGE_REQUIRED=NO",
        "REMOTE_ENDPOINT_CANDIDATE=NONE",
        "cannot be relabeled",
        "invalidation reason",
        "same-window",
        "never forces a repeat",
        "advance to the next unresolved discriminator",
    ):
        assert marker in doc, f"H&H Netstat baseline missing no-restage marker: {marker}"
    assert "SATISFIED_BY_PRIOR_PROVENANCE" in read(HH_TEST)


def test_field_workflow_binding_carries_the_decision_sequence() -> None:
    skill = read(FIELD_SKILL)
    assert "## Evidence provenance and no-restage gate" in skill
    assert (
        "missing same-run duplication is not by itself a reason to repeat operator work" in skill
    ), "field workflow lost the machine-testable no-restage phrase"
    for marker in (
        "SATISFIED_BY_PRIOR_PROVENANCE",
        "harness/api/evidence-provenance-registry.json",
        "Restage only with an explicit recorded invalidation reason",
        "advance to the next unresolved discriminator",
    ):
        assert marker in skill, f"field workflow missing provenance marker: {marker}"


def test_validator_is_registered_and_wired() -> None:
    registry = load(VALIDATORS)
    entry = next(
        (item for item in registry["validators"] if item["id"] == "evidence-provenance-contracts"),
        None,
    )
    assert entry is not None, "validator registry missing evidence-provenance-contracts"
    assert entry["command"] == "python harness/validators/validate-evidence-provenance-contracts.py"
    assert entry["blocking"] is True
    assert "harness/api/evidence-provenance-registry.json" in entry["scope"]
    validator_name = "validate-evidence-provenance-contracts.py"
    for path in (PRE_COMMIT, PRE_PUSH, CI):
        assert validator_name in read(path), f"validator not wired: {path.relative_to(ROOT).as_posix()}"
    offline = read(OFFLINE)
    assert validator_name in offline
    assert "Tests/survey/test_evidence_provenance_reuse_contracts.py" in offline


def test_no_provider_or_network_dependency() -> None:
    targets = (REGISTRY, SCHEMA, POLICY, VALIDATOR, HH_DOC, FIELD_SKILL, Path(__file__))
    joined = "\n".join(read(path) for path in targets)
    for marker in PROVIDER_MARKERS:
        assert marker not in joined, f"provider-specific marker leaked: {marker}"
    for literal in set(re.findall(r"(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?!\d)", joined)):
        address = ipaddress.ip_address(literal)
        assert address in ipaddress.ip_network("192.0.2.0/24"), f"non-TEST-NET IPv4 literal: {literal}"
    macs = set(re.findall(r"(?i)\b(?:[0-9a-f]{2}[-:]){5}[0-9a-f]{2}\b", joined))
    assert macs <= {"AA-BB-CC-DD-EE-FF"}, f"non-synthetic MAC literal: {sorted(macs)}"
    for path in (POLICY, VALIDATOR):
        assert not NETWORK_IMPORT.search(read(path)), f"network import in offline contract: {path.name}"


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: evidence provenance reuse contracts ({len(tests)} groups)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
