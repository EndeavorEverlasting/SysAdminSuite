#!/usr/bin/env python3
"""Dependency-free contracts for the developer-workstation provisioning profile."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROFILE = ROOT / "Config/developer-workstation-profile.sample.json"
SCHEMA = ROOT / "schemas/harness/developer-workstation-profile.schema.json"
DOC = ROOT / "docs/DEVELOPER_WORKSTATION_PROVISIONING.md"
MAP = ROOT / "CODEBASE_MAP.md"
RUNNER = ROOT / "tests/survey/run_offline_survey_tests.sh"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def load(path: Path) -> dict:
    return json.loads(read(path))


def test_profile_and_schema_are_fail_closed() -> None:
    profile = load(PROFILE)
    schema = load(SCHEMA)
    assert profile["schema_version"] == "sas-developer-workstation-profile/v1"
    assert profile["schema_path"] == "schemas/harness/developer-workstation-profile.schema.json"
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["$id"] == profile["schema_path"]
    assert schema["additionalProperties"] is False
    assert set(schema["required"]) == {
        "schema_version", "schema_path", "workspace", "terminal", "agent_switchboard", "posture"
    }


def test_profile_preserves_repository_ownership_boundary() -> None:
    profile = load(PROFILE)
    assert profile["terminal"] == {
        "provider": "wezterm",
        "default_environment": "wsl",
        "multiplexer": "tmux",
        "wsl_distribution": "Ubuntu",
    }
    switchboard = profile["agent_switchboard"]
    assert switchboard["repository"] == "EndeavorEverlasting/AgentSwitchboard"
    assert switchboard["invocation_mode"] == "external-versioned-contract"
    assert switchboard["required_agents"] == ["opencode", "agy", "goose"]
    posture = profile["posture"]
    assert posture == {
        "install_missing_only": True,
        "preserve_existing_configuration": True,
        "automatic_authentication": False,
        "target_mutation": False,
        "tracked_runtime_evidence": False,
    }


def test_profile_contains_no_machine_local_or_secret_material() -> None:
    text = read(PROFILE)
    assert not re.search(r"[A-Za-z]:\\", text), "tracked profile contains a Windows-local path"
    assert "/mnt/c/Users/" not in text
    forbidden = ("token", "secret", "password", "api_key", "credential")
    lowered = text.lower()
    for term in forbidden:
        assert term not in lowered, f"tracked profile contains forbidden material marker: {term}"


def test_contract_is_discoverable_and_wired() -> None:
    schema_path = "schemas/harness/developer-workstation-profile.schema.json"
    profile_path = "Config/developer-workstation-profile.sample.json"
    test_path = "Tests/survey/test_developer_workstation_profile_contracts.py"
    for path in (schema_path, profile_path):
        assert path in read(DOC), f"documentation does not name {path}"
        assert path in read(MAP), f"codebase map does not name {path}"
    assert f"python3 {test_path}" in read(RUNNER)


def test_schema_validation_when_available() -> None:
    try:
        import jsonschema
    except ImportError:
        return
    jsonschema.validate(load(PROFILE), load(SCHEMA))


def main() -> None:
    tests = [
        test_profile_and_schema_are_fail_closed,
        test_profile_preserves_repository_ownership_boundary,
        test_profile_contains_no_machine_local_or_secret_material,
        test_contract_is_discoverable_and_wired,
        test_schema_validation_when_available,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} developer workstation profile contracts")


if __name__ == "__main__":
    main()
