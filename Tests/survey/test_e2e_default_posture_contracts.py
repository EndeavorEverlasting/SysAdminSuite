#!/usr/bin/env python3
"""Contracts for SysAdminSuite's default end-to-end validation posture."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AGENTS = ROOT / "AGENTS.md"
DOCTRINE = ROOT / "docs" / "END_TO_END_TESTING_POSTURE.md"
CAPABILITY = ROOT / ".claude" / "capabilities" / "end-to-end-testing.md"
SKILL = ROOT / ".claude" / "skills" / "end-to-end-validation" / "SKILL.md"
SCOPED = ROOT / ".claude" / "skills" / "scoped-validation" / "SKILL.md"
PROFILES = ROOT / "harness" / "e2e" / "e2e-profiles.json"
SCHEMA = ROOT / "schemas" / "harness" / "e2e-validation-profiles.schema.json"
RUNNER = ROOT / "scripts" / "Invoke-SasEndToEndValidation.ps1"
WORKFLOW = ROOT / ".github" / "workflows" / "default-e2e-validation.yml"
MANIFEST = ROOT / "harness" / "api" / "agent-capability-manifest.json"

def read(path: Path) -> str:
    assert path.is_file(), f"missing required path: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")

def load(path: Path) -> dict:
    return json.loads(read(path))

def test_default_posture_is_explicit_and_not_unit_only() -> None:
    agents = read(AGENTS)
    doctrine = read(DOCTRINE)
    assert "End-to-end proof is the default merge and release target" in agents
    assert "Unit tests alone are insufficient" in doctrine
    assert "fixture, synthetic, or loopback end-to-end journey" in doctrine
    assert "Never promote fixture or loopback E2E to live target proof" in doctrine
    assert ".claude/skills/end-to-end-validation/SKILL.md" in agents

def test_skill_and_capability_compose_the_posture() -> None:
    capability = read(CAPABILITY)
    skill = read(SKILL)
    scoped = read(SCOPED)
    assert "## Contract" in capability
    assert "## Used by" in capability
    assert "end-to-end-testing.md" in skill
    assert "proof-and-checkpointing.md" in skill
    assert "mutation-and-evidence-boundaries.md" in skill
    assert "end-to-end-testing.md" in scoped
    assert "targeted check" in scoped.lower()
    assert "end-to-end" in scoped.lower()

def test_profile_is_fail_closed_and_loopback_only() -> None:
    catalog = load(PROFILES)
    schema = load(SCHEMA)
    assert catalog["schema_version"] == "sas-e2e-profiles/v1"
    assert catalog["schema_path"] == schema["$id"]
    assert schema["additionalProperties"] is False
    assert catalog["posture"] == {
        "end_to_end_default_required": True,
        "unit_tests_sufficient_for_merge": False,
        "external_network_activity_default": False,
        "target_mutation_default": False,
        "tracked_runtime_evidence_allowed": False,
    }
    profiles = {p["id"]: p for p in catalog["profiles"]}
    journeys = {j["id"]: j for j in catalog["journeys"]}
    default = profiles[catalog["default_profile"]]
    assert len(default["journey_ids"]) >= 3
    assert set(default["journey_ids"]) <= set(journeys)
    for journey_id in default["journey_ids"]:
        journey = journeys[journey_id]
        assert journey["required"] is True
        assert journey["network_scope"] in {"none", "loopback-only"}
        assert journey["target_mutation"] is False
        assert (ROOT / journey["script"]).is_file()
    scripts = {j["script"] for j in journeys.values()}
    assert "scripts/validate-sysadmin-harness.ps1" in scripts
    assert "dashboard/test_relay_cancel_e2e.py" in scripts
    assert "dashboard/test_relay_abort_e2e.js" in scripts

def test_runner_emits_gate_artifacts_and_proof_boundaries() -> None:
    text = read(RUNNER)
    for fragment in [
        "e2e_validation_matrix.txt",
        "e2e_validation_result.json",
        "fixture_or_loopback_e2e",
        "live_target_e2e=$false",
        "external_network_activity_performed",
        "target_mutation_performed",
        "missing runtime:",
    ]:
        assert fragment in text, f"runner missing contract: {fragment}"
    forbidden = [
        r"Test-NetConnection",
        r"Resolve-DnsName",
        r"Invoke-WebRequest",
        r"\bnmap\b",
        r"\bnaabu\b",
        r"Enter-PSSession",
        r"Invoke-Command\s+-ComputerName",
    ]
    for pattern in forbidden:
        assert not re.search(pattern, text, re.IGNORECASE), f"default runner contains target surface: {pattern}"

def test_ci_executes_the_real_default_journeys() -> None:
    workflow = read(WORKFLOW)
    assert "windows-latest" in workflow
    assert "pip install websockets jsonschema" in workflow
    assert "npm install --no-save --no-package-lock ws@8" in workflow
    assert "Tests\\survey\\test_e2e_default_posture_contracts.py" in workflow
    assert "Invoke-SasEndToEndValidation.ps1" in workflow
    assert "e2e_validation_result.json" in workflow
    assert "if-no-files-found: error" in workflow

def test_agent_manifest_records_e2e_default() -> None:
    manifest = load(MANIFEST)
    posture = manifest["posture"]
    assert posture["end_to_end_default_required"] is True
    assert posture["unit_tests_sufficient_for_merge"] is False
    capabilities = {item["id"]: item for item in manifest["capabilities"]}
    skills = {item["id"]: item for item in manifest["skills"]}
    assert "end-to-end-testing" in capabilities
    assert "end-to-end-validation" in skills
    assert "end-to-end-testing" in skills["end-to-end-validation"]["capability_ids"]
    assert "end-to-end-testing" in skills["scoped-validation"]["capability_ids"]

def test_schema_validation_when_jsonschema_is_available() -> None:
    try:
        import jsonschema
    except ImportError:
        return
    jsonschema.validate(load(PROFILES), load(SCHEMA))

def main() -> None:
    tests = [
        test_default_posture_is_explicit_and_not_unit_only,
        test_skill_and_capability_compose_the_posture,
        test_profile_is_fail_closed_and_loopback_only,
        test_runner_emits_gate_artifacts_and_proof_boundaries,
        test_ci_executes_the_real_default_journeys,
        test_agent_manifest_records_e2e_default,
        test_schema_validation_when_jsonschema_is_available,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} E2E default posture contracts")

if __name__ == "__main__":
    main()
