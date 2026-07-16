#!/usr/bin/env python3
"""Contracts for machine-local-path-free final sprint handoff compression."""
from __future__ import annotations
import copy
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / "schemas/harness/agent-sprint-capsule.schema.json"
FIXTURE = ROOT / "Tests/Fixtures/capsules/agent-sprint-capsule.v2.sample.json"
GENERATOR = ROOT / "tools/New-SasSprintCapsule.ps1"
RUN_CONTEXT = ROOT / "scripts/SasRunContext.psm1"
HARNESS_API = ROOT / "harness/api/sas-harness-api.json"
ROUTING = ROOT / "harness/api/agent-routing-manifest.json"
WORKFLOW_SPEC = ROOT / "harness/workflows/agent-sprint-capsule.yaml"
WORKFLOW = ROOT / ".github/workflows/agent-instruction-contracts.yml"
RUNNER = ROOT / "tests/survey/run_offline_survey_tests.sh"
LOCAL_PATTERN = re.compile(r"(?i)(?:[A-Za-z]:[\\/]|/(?:home|Users|mnt/c)/|%USERPROFILE%|\$HOME|BEGIN (?:RSA |OPENSSH )?PRIVATE KEY)")


def read(path: Path) -> str:
    assert path.is_file(), f"missing required path: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def load(path: Path):
    return json.loads(read(path))


def walk_strings(value):
    if isinstance(value, dict):
        for item in value.values():
            yield from walk_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from walk_strings(item)
    elif isinstance(value, str):
        yield value


def test_schema_and_fixture_are_closed_and_current() -> None:
    schema, fixture = load(SCHEMA), load(FIXTURE)
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["$id"] == "schemas/harness/agent-sprint-capsule.schema.json"
    assert schema["additionalProperties"] is False
    assert fixture["schema_version"] == "sas-agent-sprint-capsule/v2"
    assert fixture["schema_path"] == schema["$id"]
    assert "repo_root" not in read(SCHEMA)
    assert "worktree_path" not in read(SCHEMA)


def test_fixture_contains_no_machine_local_or_secret_material() -> None:
    fixture = load(FIXTURE)
    for value in walk_strings(fixture):
        assert not LOCAL_PATTERN.search(value), f"fixture leaks machine-local or secret-like material: {value!r}"
    assert fixture["repository"]["slug"] == "EndeavorEverlasting/SysAdminSuite"
    assert all(not path.startswith("/") for path in fixture["artifacts"]["generated"])


def test_generator_reuses_run_context_and_registry() -> None:
    generator = read(GENERATOR)
    run_context = read(RUN_CONTEXT)
    for marker in ("Import-Module", "New-SasRunContext", "Register-SasArtifact", "artifact_registry_path", "operator_handoff_path", "git -C", "status", "ConvertTo-SasRepoRelative", "AllowDirtyWorktree"):
        assert marker in generator
    assert "sas-artifact-registry/v1" in run_context
    assert "worktree_clean = $true" not in generator
    assert "repo_root" not in generator
    assert "worktree_path" not in generator
    assert "No network activity performed." in generator


def test_generator_rejects_overlap_and_local_handoff_text() -> None:
    generator = read(GENERATOR)
    for marker in ("owned and forbidden scope overlap", "machine-local path or secret-like value", "worktree is dirty", "primary skill is not uniquely routed", "generated artifact escaped the repository root"):
        assert marker in generator
    assert "Test-SasPathOverlap" in generator
    assert "Assert-SasSafeHandoffText" in generator


def test_harness_api_and_routing_register_capsule_operation() -> None:
    operations = {item["id"]: item for item in load(HARNESS_API)["operations"]}
    operation = operations["agent_sprint_capsule.generate"]
    assert operation["mode"] == "local_transform"
    assert operation["network_activity"] is False and operation["target_mutation"] is False
    assert "Uses_canonical_SasRunContext" in operation["guardrails"]
    triggers = {item["target"]: item for item in load(ROUTING)["triggers"]}
    assert triggers["agent_sprint_capsule.generate"]["target_type"] == "harness_operation"
    assert (ROOT / triggers["agent_sprint_capsule.generate"]["validators"][0]).is_file()


def test_workflow_and_validation_wiring() -> None:
    workflow_text = read(WORKFLOW_SPEC)
    assert "register-artifact" in workflow_text and "render-handoff" in workflow_text
    assert "No_machine_local_paths_in_capsule" in workflow_text
    assert "python3 Tests/survey/test_agent_sprint_capsule_contracts.py" in read(RUNNER)
    ci = read(WORKFLOW)
    assert "python3 Tests/survey/test_agent_sprint_capsule_contracts.py" in ci
    assert "Tests\\Pester\\SprintCapsule.Tests.ps1" in ci


def test_schema_rejects_local_paths_when_jsonschema_is_available() -> None:
    try:
        import jsonschema
    except ImportError:
        return
    schema, fixture = load(SCHEMA), load(FIXTURE)
    jsonschema.validate(fixture, schema)
    for bad in (r"C:\\Users\\operator\\repo", "/home/operator/repo", "/mnt/c/Users/operator/repo"):
        candidate = copy.deepcopy(fixture)
        candidate["handoff"]["next_command"] = bad
        try:
            jsonschema.validate(candidate, schema)
        except jsonschema.ValidationError:
            pass
        else:
            raise AssertionError(f"schema accepted machine-local handoff text: {bad}")


def main() -> None:
    tests = [test_schema_and_fixture_are_closed_and_current, test_fixture_contains_no_machine_local_or_secret_material, test_generator_reuses_run_context_and_registry, test_generator_rejects_overlap_and_local_handoff_text, test_harness_api_and_routing_register_capsule_operation, test_workflow_and_validation_wiring, test_schema_rejects_local_paths_when_jsonschema_is_available]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} agent sprint capsule contracts")


if __name__ == "__main__":
    main()
