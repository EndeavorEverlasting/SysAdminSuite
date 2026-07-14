#!/usr/bin/env python3
"""Dependency-free contracts for the developer-workstation provisioning profile."""
from __future__ import annotations

import copy
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


def profiles_by_id(profile: dict) -> dict[str, dict]:
    profiles = profile["terminal"]["execution_profiles"]
    ids = [item["id"] for item in profiles]
    assert len(ids) == len(set(ids)), f"duplicate execution profile ids: {ids}"
    return {item["id"]: item for item in profiles}


def test_profile_and_schema_are_fail_closed() -> None:
    profile = load(PROFILE)
    schema = load(SCHEMA)
    assert profile["schema_version"] == "sas-developer-workstation-profile/v2"
    assert profile["schema_path"] == "schemas/harness/developer-workstation-profile.schema.json"
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["$id"] == profile["schema_path"]
    assert schema["additionalProperties"] is False
    assert set(schema["required"]) == {
        "schema_version",
        "schema_path",
        "workspace",
        "platform_support",
        "terminal",
        "agent_switchboard",
        "posture",
    }


def test_platform_support_is_bimodal_and_macos_is_not_claimed() -> None:
    profile = load(PROFILE)
    assert profile["platform_support"] == {
        "supported": ["windows", "linux"],
        "unsupported": ["macos"],
        "runtime_test_available": {
            "windows": True,
            "linux": True,
            "macos": False,
        },
    }
    profiles = profiles_by_id(profile)
    assert all(item["platform"] in {"windows", "linux"} for item in profiles.values())
    assert not any(item["platform"] == "macos" for item in profiles.values())


def test_wezterm_has_enabled_native_defaults_for_windows_and_linux() -> None:
    profile = load(PROFILE)
    terminal = profile["terminal"]
    assert terminal["provider"] == "wezterm"
    assert terminal["preference"] == "required"
    assert terminal["default_profiles"] == {
        "windows": "windows-native",
        "linux": "linux-native",
    }

    profiles = profiles_by_id(profile)
    windows = profiles["windows-native"]
    linux = profiles["linux-native"]
    assert windows == {
        "id": "windows-native",
        "platform": "windows",
        "environment": "native",
        "priority": 10,
        "enabled": True,
        "shell": "pwsh",
        "multiplexer": "none",
    }
    assert linux == {
        "id": "linux-native",
        "platform": "linux",
        "environment": "native",
        "priority": 10,
        "enabled": True,
        "shell": "bash",
        "multiplexer": "tmux",
    }


def test_wsl_remains_optional_and_lower_priority() -> None:
    profiles = profiles_by_id(load(PROFILE))
    windows = profiles["windows-native"]
    wsl = profiles["wsl-tmux"]
    assert wsl["platform"] == "windows"
    assert wsl["environment"] == "wsl"
    assert wsl["enabled"] is False
    assert wsl["priority"] > windows["priority"]
    assert wsl["multiplexer"] == "tmux"
    assert wsl["distribution"] == "Ubuntu"


def test_profile_preserves_repository_ownership_and_safety_boundaries() -> None:
    profile = load(PROFILE)
    switchboard = profile["agent_switchboard"]
    assert switchboard["repository"] == "EndeavorEverlasting/AgentSwitchboard"
    assert switchboard["invocation_mode"] == "external-versioned-contract"
    assert switchboard["required_agents"] == ["opencode", "agy", "goose"]
    assert profile["posture"] == {
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
    assert "Windows and Linux" in read(DOC)
    assert "macOS" in read(DOC)
    assert f"python3 {test_path}" in read(RUNNER)


def test_schema_validation_and_rejections_when_available() -> None:
    try:
        import jsonschema
    except ImportError:
        return

    profile = load(PROFILE)
    schema = load(SCHEMA)
    jsonschema.validate(profile, schema)

    mac_profile = copy.deepcopy(profile)
    mac_profile["terminal"]["execution_profiles"].append(
        {
            "id": "macos-native",
            "platform": "macos",
            "environment": "native",
            "priority": 10,
            "enabled": True,
            "shell": "zsh",
            "multiplexer": "tmux",
        }
    )
    try:
        jsonschema.validate(mac_profile, schema)
    except jsonschema.ValidationError:
        pass
    else:
        raise AssertionError("schema accepted an unsupported macOS execution profile")

    linux_wsl = copy.deepcopy(profile)
    linux_wsl["terminal"]["execution_profiles"][1]["environment"] = "wsl"
    linux_wsl["terminal"]["execution_profiles"][1]["distribution"] = "Ubuntu"
    try:
        jsonschema.validate(linux_wsl, schema)
    except jsonschema.ValidationError:
        pass
    else:
        raise AssertionError("schema accepted WSL as a Linux-host execution environment")


def main() -> None:
    tests = [
        test_profile_and_schema_are_fail_closed,
        test_platform_support_is_bimodal_and_macos_is_not_claimed,
        test_wezterm_has_enabled_native_defaults_for_windows_and_linux,
        test_wsl_remains_optional_and_lower_priority,
        test_profile_preserves_repository_ownership_and_safety_boundaries,
        test_profile_contains_no_machine_local_or_secret_material,
        test_contract_is_discoverable_and_wired,
        test_schema_validation_and_rejections_when_available,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} developer workstation profile contracts")


if __name__ == "__main__":
    main()
