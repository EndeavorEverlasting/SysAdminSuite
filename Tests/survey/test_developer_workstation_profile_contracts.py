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


def validate_repo_path(repo_path: str) -> None:
    # Reject absolute paths (starting with slash or drive letter)
    assert not repo_path.startswith("/"), f"repo_path '{repo_path}' cannot start with a slash"
    assert not re.match(r"^[A-Za-z]:", repo_path), f"repo_path '{repo_path}' cannot start with a drive letter"
    # Reject home-relative prefix paths or env vars
    assert not repo_path.startswith("~"), f"repo_path '{repo_path}' cannot start with ~"
    assert not repo_path.startswith("%"), f"repo_path '{repo_path}' cannot start with %"
    # Reject home-relative 'dev/' prefix as it implies local home folder dev setup
    assert not repo_path.startswith("dev/"), f"repo_path '{repo_path}' cannot start with 'dev/' prefix"
    # Reject machine-local user directory paths
    assert "Users/" not in repo_path, f"repo_path '{repo_path}' cannot contain 'Users/'"
    assert "home/" not in repo_path, f"repo_path '{repo_path}' cannot contain 'home/'"
    assert "Cheex" not in repo_path, f"repo_path '{repo_path}' cannot contain the developer username 'Cheex'"


def validate_workstation_profile_invariants(profile: dict) -> None:
    # 1. Platform support check
    platform_support = profile.get("platform_support", {})
    supported = platform_support.get("supported", [])
    unsupported = platform_support.get("unsupported", [])
    assert "windows" in supported and "linux" in supported, "windows and linux must be supported"
    assert "macos" in unsupported, "macos must be unsupported"
    assert "macos" not in supported, "macos must not be supported"

    # 2. Terminal provider check
    terminal = profile.get("terminal", {})
    assert terminal.get("provider") == "wezterm", "provider must be wezterm"
    assert terminal.get("preference") == "required", "preference must be required"

    # 3. Default profiles check
    default_profiles = terminal.get("default_profiles", {})
    assert "windows" in default_profiles, "missing windows default profile"
    assert "linux" in default_profiles, "missing linux default profile"

    # 4. Profile validation
    execution_profiles = terminal.get("execution_profiles", [])
    profile_ids = [p.get("id") for p in execution_profiles]

    # Duplicate profile IDs
    assert len(profile_ids) == len(set(profile_ids)), f"duplicate execution profile ids: {profile_ids}"

    id_to_profile = {p.get("id"): p for p in execution_profiles}

    # Default profile pointing to a missing profile
    windows_default_id = default_profiles.get("windows")
    linux_default_id = default_profiles.get("linux")
    assert windows_default_id in id_to_profile, f"windows default profile '{windows_default_id}' does not exist"
    assert linux_default_id in id_to_profile, f"linux default profile '{linux_default_id}' does not exist"

    # Default profile must be enabled
    assert id_to_profile[windows_default_id].get("enabled") is True, f"default profile '{windows_default_id}' must be enabled"
    assert id_to_profile[linux_default_id].get("enabled") is True, f"default profile '{linux_default_id}' must be enabled"

    # Platform/environment checks
    for p in execution_profiles:
        # Check platform is windows or linux
        assert p.get("platform") in {"windows", "linux"}, f"unsupported platform '{p.get('platform')}' in profile '{p.get('id')}'"

        # WSL declared on a Linux host profile
        if p.get("environment") == "wsl":
            assert p.get("platform") == "windows", f"WSL environment only valid on windows platform, got platform '{p.get('platform')}'"
            # WSL profile must be disabled
            assert p.get("enabled") is False, f"WSL profile '{p.get('id')}' must be disabled"
            # WSL outranking Windows-native
            if windows_default_id in id_to_profile:
                windows_priority = id_to_profile[windows_default_id].get("priority", 10)
                assert p.get("priority", 100) > windows_priority, f"WSL profile '{p.get('id')}' priority must be lower priority (larger priority number) than windows-native"

    # 5. repo_path validation
    workspace = profile.get("workspace", {})
    repo_path = workspace.get("repo_path", "")
    validate_repo_path(repo_path)


def test_profile_contains_no_machine_local_or_secret_material() -> None:
    text = read(PROFILE)
    assert not re.search(r"[A-Za-z]:\\", text), "tracked profile contains a Windows-local path"
    assert "/mnt/c/Users/" not in text
    assert "Cheex" not in text, "tracked profile contains developer username 'Cheex'"
    forbidden = ("token", "secret", "password", "api_key", "credential")
    lowered = text.lower()
    for term in forbidden:
        assert term not in lowered, f"tracked profile contains forbidden material marker: {term}"

    # Also assert that the parsed profile passes the invariant validations
    profile = load(PROFILE)
    validate_workstation_profile_invariants(profile)


def test_negative_contract_invariants() -> None:
    profile = load(PROFILE)

    # Helper to assert failure
    def assert_validation_fails(mutated_profile: dict, expected_msg_part: str) -> None:
        try:
            validate_workstation_profile_invariants(mutated_profile)
        except AssertionError as e:
            assert expected_msg_part.lower() in str(e).lower(), f"expected error containing '{expected_msg_part}', got '{e}'"
            return
        raise AssertionError(f"mutated profile expected to fail validation for '{expected_msg_part}', but it passed")

    # Negative Case: macOS profile insertion
    p_macos = copy.deepcopy(profile)
    p_macos["terminal"]["execution_profiles"].append({
        "id": "macos-native",
        "platform": "macos",
        "environment": "native",
        "priority": 10,
        "enabled": True,
        "shell": "zsh",
        "multiplexer": "tmux"
    })
    assert_validation_fails(p_macos, "unsupported platform")

    # Negative Case: WSL declared on a Linux host profile
    p_linux_wsl = copy.deepcopy(profile)
    for p in p_linux_wsl["terminal"]["execution_profiles"]:
        if p["id"] == "linux-native":
            p["environment"] = "wsl"
    assert_validation_fails(p_linux_wsl, "wsl environment only valid on windows platform")

    # Negative Case: missing Windows native default
    p_missing_windows = copy.deepcopy(profile)
    del p_missing_windows["terminal"]["default_profiles"]["windows"]
    assert_validation_fails(p_missing_windows, "missing windows default profile")

    # Negative Case: missing Linux native default
    p_missing_linux = copy.deepcopy(profile)
    del p_missing_linux["terminal"]["default_profiles"]["linux"]
    assert_validation_fails(p_missing_linux, "missing linux default profile")

    # Negative Case: disabled default profile
    p_disabled_default = copy.deepcopy(profile)
    for p in p_disabled_default["terminal"]["execution_profiles"]:
        if p["id"] == "windows-native":
            p["enabled"] = False
    assert_validation_fails(p_disabled_default, "must be enabled")

    # Negative Case: duplicate profile IDs
    p_duplicate_ids = copy.deepcopy(profile)
    p_duplicate_ids["terminal"]["execution_profiles"].append(
        copy.deepcopy(profile["terminal"]["execution_profiles"][0])
    )
    assert_validation_fails(p_duplicate_ids, "duplicate execution profile ids")

    # Negative Case: default profile pointing to a missing profile
    p_missing_ref = copy.deepcopy(profile)
    p_missing_ref["terminal"]["default_profiles"]["windows"] = "non-existent-profile"
    assert_validation_fails(p_missing_ref, "does not exist")

    # Negative Case: WSL outranking Windows-native
    p_wsl_outrank = copy.deepcopy(profile)
    for p in p_wsl_outrank["terminal"]["execution_profiles"]:
        if p["id"] == "wsl-tmux":
            p["priority"] = 5
    assert_validation_fails(p_wsl_outrank, "must be lower priority")

    # Negative Case: home-relative paths (starting with dev/)
    p_home_dev = copy.deepcopy(profile)
    p_home_dev["workspace"]["repo_path"] = "dev/SysAdminSuite"
    assert_validation_fails(p_home_dev, "cannot start with 'dev/' prefix")

    # Negative Case: machine-local paths (Windows path)
    p_win_local = copy.deepcopy(profile)
    p_win_local["workspace"]["repo_path"] = "C:\\Users\\Cheex\\SysAdminSuite"
    assert_validation_fails(p_win_local, "cannot start with a drive letter")

    # Negative Case: machine-local paths (Linux absolute path)
    p_lin_local = copy.deepcopy(profile)
    p_lin_local["workspace"]["repo_path"] = "/home/Cheex/SysAdminSuite"
    assert_validation_fails(p_lin_local, "cannot start with a slash")

    # Negative Case: path containing user directory 'Cheex'
    p_cheex_local = copy.deepcopy(profile)
    p_cheex_local["workspace"]["repo_path"] = "projects/Cheex/SysAdminSuite"
    assert_validation_fails(p_cheex_local, "cannot contain the developer username 'Cheex'")

    # Negative Case: path containing 'Users/'
    p_users_local = copy.deepcopy(profile)
    p_users_local["workspace"]["repo_path"] = "Users/someuser/SysAdminSuite"
    assert_validation_fails(p_users_local, "cannot contain 'Users/'")


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
        test_negative_contract_invariants,
        test_contract_is_discoverable_and_wired,
        test_schema_validation_and_rejections_when_available,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} developer workstation profile contracts")


if __name__ == "__main__":
    main()
