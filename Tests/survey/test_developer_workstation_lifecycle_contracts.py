#!/usr/bin/env python3
"""Contracts for the developer-workstation lifecycle evidence spine."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUN_SCHEMA = ROOT / "schemas/harness/developer-workstation-run.schema.json"
RESULT_SCHEMA = ROOT / "schemas/harness/developer-workstation-lifecycle-result.schema.json"
REGISTRY = ROOT / "harness/api/developer-workstation-artifact-types.json"
FIXTURES = ROOT / "Tests/Fixtures/developer-workstation-lifecycle"
API = ROOT / "harness/api/sas-harness-api.json"
IGNORE = ROOT / ".gitignore"
WORKFLOW = ROOT / ".github/workflows/developer-workstation-lifecycle-contracts.yml"
RUNNER = ROOT / "tests/survey/run_offline_survey_tests.sh"

OPERATIONS = {
    "inventory", "plan", "install", "configure", "start", "attach", "status", "stop",
    "agent-readiness", "rollback", "fixture-e2e", "live-runtime",
}
STATES = {
    "absent", "planned", "installed", "configured", "backend-running", "tmux-available",
    "session-running", "gui-launched", "attached", "agent-ready", "action-required", "failed", "stopped",
}
REASONS = {
    "none", "no-wsl-distro", "docker-only-distro", "tmux-missing", "wsl-stopped",
    "keepalive-missing", "keepalive-stale", "tmux-socket-missing", "nested-tmux-attempt",
    "wezterm-cli-gui-confusion", "invalid-lua", "unavailable-font", "windows-only-agent-bridge",
    "authentication-required", "rollback-required", "unsupported-platform", "operation-timeout",
    "malformed-agent-result",
}
PROOF_FLAGS = {
    "install_completed", "config_applied", "launcher_started", "tmux_attached",
    "command_acknowledged", "behavior_observed", "persistence_observed", "live_runtime",
    "operator_accepted",
}
ARTIFACT_ROLES = {
    "inventory", "plan", "config-backup-manifest", "lua-validation", "backend-status",
    "tmux-status", "launcher-result", "agentswitchboard-result", "rollback-result",
    "english-summary", "runtime-proof",
}


def load(path: Path) -> dict:
    assert path.is_file(), f"missing {path.relative_to(ROOT).as_posix()}"
    return json.loads(path.read_text(encoding="utf-8"))


def enum_at(schema: dict, *segments) -> set[str]:
    node = schema
    for segment in segments:
        node = node[segment]
    return set(node["enum"])


def test_schema_versions_and_closed_vocabularies() -> None:
    run = load(RUN_SCHEMA)
    result = load(RESULT_SCHEMA)
    assert run["additionalProperties"] is False
    assert result["additionalProperties"] is False
    assert run["properties"]["schema_version"]["const"] == "sas-developer-workstation-run/v1"
    assert result["properties"]["schema_version"]["const"] == "sas-developer-workstation-lifecycle-result/v1"
    assert enum_at(run, "properties", "operation") == OPERATIONS
    assert enum_at(result, "properties", "operation") == OPERATIONS
    assert enum_at(result, "properties", "lifecycle_state") == STATES
    assert enum_at(result, "properties", "reason_codes", "items") == REASONS
    assert set(result["properties"]["proof"]["required"]) == PROOF_FLAGS


def test_artifact_registry_is_canonical_and_complete() -> None:
    registry = load(REGISTRY)
    assert registry["schema_version"] == "sas-developer-workstation-artifact-types/v1"
    assert registry["workflow_id"] == "developer-workstation"
    assert registry["tracked_runtime_evidence"] is False
    assert set(registry["roles"]) == ARTIFACT_ROLES
    result = load(RESULT_SCHEMA)
    schema_roles = enum_at(result, "$defs", "artifactReference", "properties", "role")
    assert schema_roles == ARTIFACT_ROLES


def validate_fixture(fixture: dict) -> None:
    assert fixture["schema_version"] == "sas-developer-workstation-lifecycle-result/v1"
    assert fixture["workflow_id"] == "developer-workstation"
    assert fixture["operation"] in OPERATIONS
    assert fixture["lifecycle_state"] in STATES
    assert set(fixture["reason_codes"]) <= REASONS
    assert set(fixture["proof"]) == PROOF_FLAGS
    assert all(value is False for value in fixture["proof"].values())
    for artifact in fixture["artifacts"]:
        assert artifact["role"] in ARTIFACT_ROLES
        assert artifact["contains_live_data"] is False
        assert not re.search(r"[A-Za-z]:\\\\|/home/|/Users/|Cheex", json.dumps(artifact))
    if fixture["outcome"] == "success":
        assert fixture["reason_codes"] == ["none"]
    if fixture["outcome"] in {"failure", "action-required", "unsupported"}:
        assert fixture["reason_codes"] and "none" not in fixture["reason_codes"]


def test_fixture_matrix_is_sanitized_and_proof_flags_default_false() -> None:
    files = sorted(FIXTURES.glob("*.fixture.json"))
    assert [path.stem for path in files] == [
        "action-required.fixture", "failure.fixture", "partial.fixture", "success.fixture", "unsupported.fixture"
    ]
    outcomes = set()
    for path in files:
        text = path.read_text(encoding="utf-8")
        assert "Cheex" not in text and "C:\\Users" not in text and "/home/" not in text
        fixture = json.loads(text)
        validate_fixture(fixture)
        outcomes.add(fixture["outcome"])
    assert outcomes == {"success", "partial", "failure", "action-required", "unsupported"}


def test_fixtures_validate_against_json_schema_when_available() -> None:
    try:
        import jsonschema
    except ImportError:
        return
    schema = load(RESULT_SCHEMA)
    for path in FIXTURES.glob("*.fixture.json"):
        jsonschema.validate(load(path), schema)


def test_harness_api_workflow_and_ignore_registration() -> None:
    api = load(API)
    operation = next(item for item in api["operations"] if item["id"] == "developer_workstation.lifecycle")
    assert operation["mode"] == "operator_execute"
    assert operation["target_mutation"] is False
    assert operation["outputs"] == [
        "developer-workstation-lifecycle-result.json", "artifact_registry.json", "english-summary.txt"
    ]
    workflow = WORKFLOW.read_text(encoding="utf-8")
    assert "test_developer_workstation_lifecycle_contracts.py" in workflow
    assert "developer-workstation-lifecycle-result.schema.json" in workflow
    assert "python -m json.tool" in workflow
    assert "python3 Tests/survey/test_developer_workstation_lifecycle_contracts.py" in RUNNER.read_text(encoding="utf-8")
    ignore = IGNORE.read_text(encoding="utf-8")
    assert "runs/" in ignore
    assert "workstation-runtime/" in ignore


def main() -> None:
    tests = [
        test_schema_versions_and_closed_vocabularies,
        test_artifact_registry_is_canonical_and_complete,
        test_fixture_matrix_is_sanitized_and_proof_flags_default_false,
        test_fixtures_validate_against_json_schema_when_available,
        test_harness_api_workflow_and_ignore_registration,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} developer workstation lifecycle contracts")


if __name__ == "__main__":
    main()
