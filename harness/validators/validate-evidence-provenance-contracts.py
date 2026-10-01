#!/usr/bin/env python3
"""Validate the offline evidence-provenance reuse and no-restage contract.

Deterministic and network-free: proves artifact provenance and discriminator
satisfaction stay separate states, prior provenance can satisfy a current
discriminator without relabeling its RUN_ID, missing same-run duplication alone
never forces restage, and explicit invalidation, conflict, and window coupling
still reopen or block reuse.
"""
from __future__ import annotations

import ipaddress
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "harness/api/evidence-provenance-registry.json"
SCHEMA = ROOT / "schemas/harness/evidence-provenance-registry.schema.json"
POLICY = ROOT / "harness/api/evidence_provenance_policy.py"
VALIDATOR_REGISTRY = ROOT / "harness/api/harness-validator-registry.json"
HH_DOC = ROOT / "docs/HH_CC_READER_NETSTAT_BASELINE.md"
FIELD_SKILL = ROOT / ".claude/skills/field-workflow/SKILL.md"
TEST = ROOT / "Tests/survey/test_evidence_provenance_reuse_contracts.py"
HH_TEST = ROOT / "Tests/survey/test_hh_cc_reader_field_probe_contracts.py"
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
IPV4 = re.compile(r"(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?!\d)")
MAC = re.compile(r"(?i)\b(?:[0-9a-f]{2}[-:]){5}[0-9a-f]{2}\b")
TEST_NET = ipaddress.ip_network("192.0.2.0/24")


def read(path: Path) -> str:
    assert path.is_file(), f"missing evidence-provenance component: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def tracked(path: Path) -> bool:
    relative = path.relative_to(ROOT).as_posix()
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", relative],
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


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


def test_registry_schema_parity() -> None:
    registry = load(REGISTRY)
    schema = load(SCHEMA)
    assert registry["schema_version"] == "sas-evidence-provenance-registry/v1"
    assert registry["repository"] == "EndeavorEverlasting/SysAdminSuite"
    assert schema["$schema"].endswith("draft/2020-12/schema")
    assert schema["properties"]["schema_version"]["const"] == registry["schema_version"]
    for key, value in registry["policy"].items():
        assert value is True, f"provenance policy disabled: {key}"
    assert registry["restage_rule"] == {
        "missing_same_run_duplication_is_not_by_itself_a_reason_to_repeat_operator_work": True,
        "restage_requires_recorded_invalidation_reason": True,
    }
    try:
        import jsonschema  # type: ignore
    except ImportError:
        pass
    else:
        jsonschema.Draft202012Validator(schema).validate(registry)


def test_canonical_state_vocabulary() -> None:
    registry = load(REGISTRY)
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
    assert {item["id"] for item in registry["freshness_classes"]} == {
        "STABLE",
        "CONFIGURATION_SENSITIVE",
        "VOLATILE",
        "WINDOW_COUPLED",
    }
    assert len(registry["reuse_conditions"]) == 6


def test_semantic_invariants(evaluate) -> None:
    # PRIOR_RUN may map to SATISFIED_BY_PRIOR_PROVENANCE...
    reused = evaluate(satisfied_baseline())
    assert reused["discriminator_state"] == "SATISFIED_BY_PRIOR_PROVENANCE"
    assert reused["restage_required"] is False
    # ...without mutating the artifact's original RUN_ID or provenance.
    assert reused["artifact_run_id"] == "OLD_RUN"
    assert reused["current_run_id"] == "NEW_RUN"
    assert reused["artifact_provenance"] == "PRIOR_RUN"

    # A missing current-run duplicate alone never yields a restage requirement.
    missing = evaluate(satisfied_baseline(current_duplicate_present=False))
    assert missing["current_run_artifact_state"] == "MISSING"
    assert missing["discriminator_state"] == "SATISFIED_BY_PRIOR_PROVENANCE"
    assert missing["discriminator_state"] != "STALE_REVALIDATION_REQUIRED"
    assert missing["restage_required"] is False

    # An explicit invalidation reason can require restage.
    invalidated = evaluate(satisfied_baseline(invalidation_reason="RELEVANT_SOFTWARE_STATE_CHANGED"))
    assert invalidated["discriminator_state"] == "STALE_REVALIDATION_REQUIRED"
    assert invalidated["restage_required"] is True
    assert invalidated["restage_allowed"] is True

    # CONFLICT fails closed instead of silently reusing prior evidence.
    conflict = evaluate(satisfied_baseline(conflicting_newer_evidence=True))
    assert conflict["discriminator_state"] == "CONFLICT"
    assert conflict["fail_closed"] is True
    assert conflict["restage_allowed"] is True

    # Window-coupled claims cannot combine unrelated runs.
    cross_window = evaluate(
        satisfied_baseline(
            artifact_run_id="RUN_A",
            current_run_id="RUN_B",
            freshness_class="WINDOW_COUPLED",
            requires_same_window=True,
            same_window=False,
        )
    )
    assert cross_window["discriminator_state"] not in {
        "SATISFIED_CURRENT_RUN",
        "SATISFIED_BY_PRIOR_PROVENANCE",
    }
    assert cross_window["reason"] == "SAME_WINDOW_TEMPORAL_COMPARISON_REQUIRED"

    # An unknown prior reader cannot satisfy a current-reader discriminator.
    foreign_reader = evaluate(satisfied_baseline(identity_compatible=False))
    assert foreign_reader["discriminator_state"] == "UNSATISFIED"
    assert foreign_reader["restage_required"] is True

    # Legitimate revalidation stays admitted for every recorded reason.
    for reason in (
        "READER_IDENTITY_INCOMPATIBLE",
        "RELEVANT_SOFTWARE_STATE_CHANGED",
        "PRIOR_EVIDENCE_INCOMPLETE",
        "NEWER_EVIDENCE_CONFLICT",
        "FRESHNESS_POLICY_EXHAUSTED",
        "SAME_WINDOW_TEMPORAL_COMPARISON_REQUIRED",
    ):
        result = evaluate(satisfied_baseline(invalidation_reason=reason))
        assert result["restage_allowed"] is True, f"revalidation blocked: {reason}"


def test_bindings_resolve() -> None:
    registry = load(REGISTRY)
    binding_ids = [item["id"] for item in registry["bindings"]]
    assert len(binding_ids) == len(set(binding_ids)), "duplicate provenance binding id"
    for binding in registry["bindings"]:
        target = ROOT / binding["path"]
        text = read(target)
        for marker in binding["required_markers"]:
            assert marker in text, f"binding {binding['id']} lost marker: {marker}"
    assert "harness/api/evidence-provenance-registry.json" in read(HH_DOC)
    assert "SATISFIED_BY_PRIOR_PROVENANCE" in read(HH_TEST)


def test_provider_neutrality_and_offline_posture() -> None:
    # HH_TEST intentionally holds the provider-marker literal for its own scan;
    # it audits only the tracked field docs, so it is excluded from this join.
    targets = (REGISTRY, SCHEMA, POLICY, Path(__file__), TEST, HH_DOC, FIELD_SKILL)
    joined = "\n".join(read(path) for path in targets)
    for marker in PROVIDER_MARKERS:
        assert marker not in joined, f"provider-specific marker leaked: {marker}"
    for literal in IPV4.findall(joined):
        address = ipaddress.ip_address(literal)
        assert address in TEST_NET, f"non-TEST-NET IPv4 literal: {literal}"
    assert set(MAC.findall(joined)) <= {"AA-BB-CC-DD-EE-FF"}, "non-synthetic MAC literal present"
    for path in (POLICY, Path(__file__), TEST):
        assert not NETWORK_IMPORT.search(read(path)), f"network import in offline contract: {path.name}"


def test_wiring() -> None:
    registry = load(VALIDATOR_REGISTRY)
    matches = [item for item in registry["validators"] if item["id"] == "evidence-provenance-contracts"]
    assert len(matches) == 1, "validator registry must contain exactly one evidence-provenance entry"
    entry = matches[0]
    assert entry["command"] == "python harness/validators/validate-evidence-provenance-contracts.py"
    assert entry["blocking"] is True
    assert entry["scope"], "validator scope missing"
    for required_scope in (
        "harness/api/evidence-provenance-registry.json",
        "schemas/harness/evidence-provenance-registry.schema.json",
        "harness/api/evidence_provenance_policy.py",
        "docs/HH_CC_READER_NETSTAT_BASELINE.md",
        ".claude/skills/field-workflow/SKILL.md",
    ):
        assert required_scope in entry["scope"], f"validator scope missing: {required_scope}"
    validator_name = "validate-evidence-provenance-contracts.py"
    for path in (PRE_COMMIT, PRE_PUSH, CI, OFFLINE):
        assert validator_name in read(path), f"validator not wired: {path.relative_to(ROOT).as_posix()}"
    assert "Tests/survey/test_evidence_provenance_reuse_contracts.py" in read(OFFLINE)


def test_components_are_tracked() -> None:
    for path in (REGISTRY, SCHEMA, POLICY, Path(__file__), TEST, HH_DOC, FIELD_SKILL, CI, HH_TEST):
        assert tracked(path), f"evidence-provenance component is not tracked: {path.relative_to(ROOT)}"


def main() -> int:
    test_registry_schema_parity()
    test_canonical_state_vocabulary()

    import sys

    sys.path.insert(0, str(ROOT))
    from harness.api.evidence_provenance_policy import evaluate

    test_semantic_invariants(evaluate)
    test_bindings_resolve()
    test_provider_neutrality_and_offline_posture()
    test_wiring()
    test_components_are_tracked()
    print("PASS: evidence provenance reuse and no-restage contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
