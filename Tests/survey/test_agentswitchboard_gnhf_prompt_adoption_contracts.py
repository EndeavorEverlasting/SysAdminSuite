#!/usr/bin/env python3
"""Focused offline contracts for SysAdminSuite AgentSwitchboard GNHF adoption."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PIN = ROOT / "harness/api/agentswitchboard-gnhf-external-contract.json"
PIN_SCHEMA = ROOT / "schemas/harness/agentswitchboard-gnhf-external-contract.schema.json"
CAPABILITIES = ROOT / "harness/api/agent-capability-manifest.json"
ROUTING = ROOT / "harness/api/agent-routing-manifest.json"
HARNESS_API = ROOT / "harness/api/sas-harness-api.json"
WORKFLOW = ROOT / "harness/workflows/agentswitchboard-gnhf-prompt-adoption.yaml"
CAPSULE_WORKFLOW = ROOT / "harness/workflows/agent-sprint-capsule.yaml"
SKILL = ROOT / ".claude/skills/gnhf-prompt-adoption/SKILL.md"
FIXTURES = ROOT / "Tests/Fixtures/agentswitchboard-gnhf-adoption"
RUNNER = ROOT / "tests/survey/run_offline_survey_tests.sh"
CI = ROOT / ".github/workflows/agent-instruction-contracts.yml"
LOCAL_OR_SECRET = re.compile(
    r"(?im)(?:(?:^|[\s\"'])[A-Za-z]:[\\/]|/(?:home|Users|mnt/c)/|BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{12,}|AKIA[0-9A-Z]{12,})"
)

EXPECTED_COMMIT = "720e2b1f1b171949a8e8e9233f4162bdd2581937"
EXPECTED_BLOBS = {
    "regular-sprint-request": "3bd3a3e778380b3e5bb95735860ce94395669a08",
    "compiled-gnhf-prompt-result": "cd6041e4ea21d30c6fc30aa8722c5df1d9cec4d6",
    "desktop-gnhf-launch-request": "3f42c92e75a1313028083e4bdf00566c176ec6e9",
    "desktop-gnhf-runtime-result": "d51e38df6d00cb26f264738272fb303e46911f6e",
}
EXPECTED_CAPABILITIES = {
    "agentswitchboard-gnhf-request-construction",
    "agentswitchboard-gnhf-external-contract-validation",
    "agentswitchboard-gnhf-prompt-compilation-delegation",
    "agentswitchboard-gnhf-local-runtime-delegation",
    "agentswitchboard-gnhf-result-ingestion",
    "agentswitchboard-gnhf-sprint-capsule-generation",
}
EXPECTED_SIGNALS = {
    "generate a good night have fun prompt",
    "run this GNHF sprint locally",
    "configure my GNHF environment",
    "execute this registered workflow overnight",
}


def read(path: Path) -> str:
    assert path.is_file(), f"missing required path: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def load(path: Path):
    return json.loads(read(path))


def test_external_contract_pin_is_exact_and_schema_backed() -> None:
    pin, schema = load(PIN), load(PIN_SCHEMA)
    assert pin["schema_version"] == "sas-agentswitchboard-gnhf-external-contract/v1"
    assert pin["supported_external_schema_version"] == 1
    assert pin["authority"] == {
        "repository": "EndeavorEverlasting/AgentSwitchboard",
        "pull_request": 17,
        "source_commit": EXPECTED_COMMIT,
        "runtime_owner": "AgentSwitchboard",
        "consumer_owner": "SysAdminSuite",
    }
    by_kind = {item["kind"]: item for item in pin["schemas"]}
    assert set(by_kind) == set(EXPECTED_BLOBS)
    assert {kind: item["git_blob_sha"] for kind, item in by_kind.items()} == EXPECTED_BLOBS
    assert all(item["schema_version"] == 1 for item in by_kind.values())
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["$id"] == pin["schema_path"] and schema["additionalProperties"] is False
    assert pin["invocation"]["plan_default"] is True
    assert set(pin["invocation"]["parameters"]) == {
        "-RequestPath", "-CompiledPromptPath", "-TargetRepo", "-PlanOnly", "-Run", "-CreateDisposableProofRepo"
    }
    assert not any((ROOT / item["path"]).exists() for item in pin["schemas"]), "external schemas must not be copied into SysAdminSuite"


def test_external_pin_schema_validates_when_jsonschema_is_available() -> None:
    try:
        import jsonschema
    except ImportError:
        return
    jsonschema.validate(load(PIN), load(PIN_SCHEMA))


def test_skill_composes_six_atomic_capabilities_and_one_route() -> None:
    manifest = load(CAPABILITIES)
    skill = next(item for item in manifest["skills"] if item["id"] == "gnhf-prompt-adoption")
    assert set(skill["capability_ids"]) == EXPECTED_CAPABILITIES
    manifest_caps = {item["id"]: item for item in manifest["capabilities"]}
    skill_text = read(SKILL)
    for capability_id in EXPECTED_CAPABILITIES:
        capability = manifest_caps[capability_id]
        text = read(ROOT / capability["path"])
        assert len(text.splitlines()) <= 80 and "## Contract" in text and "## Used by" in text
        assert capability_id + ".md" in skill_text
    routes = [item for item in load(ROUTING)["triggers"] if item["target"] == "gnhf-prompt-adoption"]
    assert len(routes) == 1 and routes[0]["target_type"] == "skill"
    assert set(routes[0]["deterministic_task_signals"]) == EXPECTED_SIGNALS


def test_activation_semantics_are_distinct_and_fail_closed() -> None:
    skill = read(SKILL)
    workflow = read(WORKFLOW)
    for marker in (
        "stop after one compiled prompt",
        "require explicit local execution authorization",
        "delegate AgentSwitchboard Plan first",
        "registered SysAdminSuite workflow plus explicit execution authorization",
        "conflicting or unknown intent returns to `repository-sprint`",
    ):
        assert marker in skill
    for marker in (
        "Compile_only_never_runs",
        "Local_execution_requires_explicit_authorization",
        "Environment_configuration_is_Plan_first",
        "Registered_overnight_workflow_requires_explicit_execution_authorization",
        "Unknown_or_conflicting_signals_fail_closed_to_repository_sprint",
    ):
        assert marker in workflow


def test_registered_workflow_and_harness_operations_are_bounded() -> None:
    try:
        import yaml
    except ImportError:
        workflow = None
    else:
        workflow = yaml.safe_load(read(WORKFLOW))
    if workflow is not None:
        assert workflow["mode"] == "local_transform"
        assert workflow["network_activity"] is False and workflow["target_mutation"] is False
        assert [phase["capability"] for phase in workflow["phases"]][1:] == [
            "agentswitchboard-gnhf-request-construction",
            "agentswitchboard-gnhf-external-contract-validation",
            "agentswitchboard-gnhf-prompt-compilation-delegation",
            "agentswitchboard-gnhf-local-runtime-delegation",
            "agentswitchboard-gnhf-result-ingestion",
            "agentswitchboard-gnhf-sprint-capsule-generation",
        ]
    operations = {item["id"]: item for item in load(HARNESS_API)["operations"]}
    expected = {
        "agentswitchboard_gnhf.prompt_compile": "local_transform",
        "agentswitchboard_gnhf.local_delegate": "operator_execute",
        "agentswitchboard_gnhf.environment_plan": "plan_only",
        "agentswitchboard_gnhf.result_ingest": "local_transform",
    }
    for operation_id, mode in expected.items():
        operation = operations[operation_id]
        assert operation["mode"] == mode
        assert operation["network_activity"] is False and operation["target_mutation"] is False
    assert "Explicit_local_execution_authorization_required" in operations["agentswitchboard_gnhf.local_delegate"]["guardrails"]
    assert "Plan_only" in operations["agentswitchboard_gnhf.environment_plan"]["guardrails"]


def test_compile_only_request_is_valid_and_missing_scope_fails() -> None:
    required = {
        "kind", "schemaVersion", "objective", "repository", "ownedScope", "forbiddenScope",
        "expectedArtifacts", "safetyConstraints", "desiredProofLevel",
    }
    valid = load(FIXTURES / "valid.compile-only.request.json")
    invalid = load(FIXTURES / "invalid.missing-scope.request.json")
    assert set(valid) == required and valid["kind"] == "regular-sprint-request" and valid["schemaVersion"] == 1
    assert valid["ownedScope"] and valid["forbiddenScope"]
    assert required - set(invalid) == {"ownedScope"}


def test_conflicting_git_modes_and_permission_fail_closed() -> None:
    conflicting = load(FIXTURES / "invalid.conflicting-git-modes.compiled-result.json")
    assert conflicting["kind"] == "compiled-gnhf-prompt-result"
    assert set(conflicting["gitExecution"]) - {"mode", "baseBranch"} == {"currentBranch"}
    denied = load(FIXTURES / "invalid.local-execution-without-permission.json")
    assert denied["operation"] == "local_execute" and denied["local_execution_authorized"] is False
    assert denied["expected"] == {"status": "rejected", "classification": "LOCAL_EXECUTION_PERMISSION_REQUIRED"}


def test_unavailable_and_version_mismatch_are_non_success() -> None:
    unavailable = load(FIXTURES / "blocked.agentswitchboard-unavailable.json")
    mismatch = load(FIXTURES / "invalid.schema-version-mismatch.json")
    assert unavailable["agentswitchboard_available"] is False
    assert unavailable["expected"] == {"status": "blocked", "classification": "AGENTSWITCHBOARD_UNAVAILABLE"}
    assert mismatch["requested_schema_version"] != load(PIN)["supported_external_schema_version"]
    assert mismatch["expected"] == {"status": "rejected", "classification": "EXTERNAL_SCHEMA_VERSION_MISMATCH"}


def test_compile_validation_and_success_result_preserve_proof_ceiling() -> None:
    validation = load(FIXTURES / "valid.compiled-prompt-validation.json")
    assert validation["valid"] is True and validation["external_schema_version"] == 1
    assert validation["external_source_commit"] == EXPECTED_COMMIT
    assert "-PlanOnly" in validation["exact_local_next_command"] and " -Run" not in validation["exact_local_next_command"]
    result = load(FIXTURES / "valid.successful-delegation-result.json")
    assert result["kind"] == "desktop-gnhf-runtime-result" and result["schemaVersion"] == 1
    assert result["status"] == "succeeded" and result["process"]["exitCode"] == 0
    assert result["commitProof"]["observed"] is True and result["commitProof"]["commitsAhead"] > 0
    assert result["artifacts"] and all(item["observed"] for item in result["artifacts"])
    registration = load(FIXTURES / "valid.sprint-capsule-registration.json")
    assert registration["operation"] == "agent_sprint_capsule.generate"
    assert registration["workflow"] == CAPSULE_WORKFLOW.relative_to(ROOT).as_posix()
    assert registration["source_proof_ceiling"] == result["proofCeiling"]
    assert registration["proof_ceiling_preserved"] is True and registration["tracked_runtime_evidence"] is False


def test_fixtures_are_sanitized_and_validation_is_wired() -> None:
    for path in FIXTURES.glob("*.json"):
        text = read(path)
        json.loads(text)
        assert not LOCAL_OR_SECRET.search(text), f"fixture leaks machine-local or secret-like material: {path.name}"
    test_path = "Tests/survey/test_agentswitchboard_gnhf_prompt_adoption_contracts.py"
    assert f"python3 {test_path}" in read(RUNNER)
    assert f"python3 {test_path}" in read(CI)
    assert "harness/workflows/agentswitchboard-gnhf-prompt-adoption.yaml" in read(CI)


def main() -> None:
    tests = [
        test_external_contract_pin_is_exact_and_schema_backed,
        test_external_pin_schema_validates_when_jsonschema_is_available,
        test_skill_composes_six_atomic_capabilities_and_one_route,
        test_activation_semantics_are_distinct_and_fail_closed,
        test_registered_workflow_and_harness_operations_are_bounded,
        test_compile_only_request_is_valid_and_missing_scope_fails,
        test_conflicting_git_modes_and_permission_fail_closed,
        test_unavailable_and_version_mismatch_are_non_success,
        test_compile_validation_and_success_result_preserve_proof_ceiling,
        test_fixtures_are_sanitized_and_validation_is_wired,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} AgentSwitchboard GNHF prompt adoption contracts")


if __name__ == "__main__":
    main()
