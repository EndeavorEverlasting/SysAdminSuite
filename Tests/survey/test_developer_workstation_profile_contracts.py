#!/usr/bin/env python3
"""Dependency-free contracts for the persistent developer-workstation profile."""
from __future__ import annotations

import copy
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROFILE = ROOT / "Config/developer-workstation-profile.sample.json"
SCHEMA = ROOT / "schemas/harness/developer-workstation-profile.schema.json"
DOC = ROOT / "docs/DEVELOPER_WORKSTATION_PROVISIONING.md"
LEDGER = ROOT / "docs/DEVELOPER_WORKSTATION_PR_STACK.md"
MAP = ROOT / "CODEBASE_MAP.md"
RUNNER = ROOT / "tests/survey/run_offline_survey_tests.sh"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def load(path: Path) -> dict:
    return json.loads(read(path))


def by_id(items: list[dict]) -> dict[str, dict]:
    ids = [item["id"] for item in items]
    assert len(ids) == len(set(ids)), f"duplicate ids: {ids}"
    return {item["id"]: item for item in items}


def validate_profile(profile: dict) -> None:
    assert profile["schema_version"] == "sas-developer-workstation-profile/v3"
    assert profile["platform_support"]["supported"] == ["windows", "linux"]
    assert profile["platform_support"]["unsupported"] == ["macos"]
    assert profile["platform_support"]["runtime_test_available"]["macos"] is False

    architecture = profile["architecture"]
    assert architecture["terminal"] == {
        "provider": "wezterm",
        "role": "terminal-host",
        "preference": "preferred",
        "gui_executable_role": "wezterm-gui",
        "cli_executable_role": "wezterm-cli",
    }
    assert architecture["workspace"] == {
        "multiplexer": "tmux",
        "display_name": "tmux: Development",
        "session_name": "dev",
    }
    assert architecture["default_backends"] == {
        "windows": "windows-wsl",
        "linux": "linux-native",
    }

    backends = by_id(architecture["tmux_backends"])
    assert set(backends) == {"windows-wsl", "linux-native"}
    for backend in backends.values():
        assert backend["multiplexer"] == "tmux"
        assert backend["tmux_capable"] is True
        assert backend["shell"] == "bash"
        assert backend["enabled"] is True
        assert backend["execution_domain"] != "windows-native"

    windows = backends["windows-wsl"]
    assert windows["host_platform"] == "windows"
    assert windows["kind"] == "wsl"
    assert windows["execution_domain"] == "windows-wsl"
    selector = windows["distro_selector"]
    assert selector["mode"] == "detected-non-docker"
    assert "docker-desktop" in selector["excluded_names"]

    linux = backends["linux-native"]
    assert linux["host_platform"] == "linux"
    assert linux["kind"] == "native-linux"
    assert linux["execution_domain"] == "linux-native"
    assert "distro_selector" not in linux
    assert windows["execution_domain"] != linux["execution_domain"]

    fallbacks = by_id(architecture["fallback_profiles"])
    powershell = fallbacks["windows-powershell"]
    assert powershell["execution_domain"] == "windows-native"
    assert powershell["shell"] == "pwsh"
    assert powershell["multiplexer"] == "none"
    assert powershell["role"] == "fallback-admin"

    switchboard = profile["agent_switchboard"]
    assert switchboard["repository"] == "EndeavorEverlasting/AgentSwitchboard"
    assert switchboard["contract_version"] == "agentswitchboard-invocation/v2"
    assert switchboard["required_agents"] == ["opencode", "agy", "goose"]
    assert switchboard["readiness_scope"] == "per-execution-domain"
    assert switchboard["windows_command_presence_satisfies_wsl_readiness"] is False
    assert switchboard["native_preference"] is True

    posture = profile["posture"]
    assert posture == {
        "install_missing_only": True,
        "preserve_existing_configuration": True,
        "automatic_authentication": False,
        "target_mutation": False,
        "tracked_runtime_evidence": False,
        "macos_implementation": False,
    }

    repo_path = profile["project"]["repo_path"]
    assert not repo_path.startswith(("/", "~", "%"))
    assert not re.match(r"^[A-Za-z]:", repo_path)
    assert ".." not in Path(repo_path).parts


def assert_invalid(mutator, expected: str) -> None:
    profile = copy.deepcopy(load(PROFILE))
    mutator(profile)
    try:
        validate_profile(profile)
    except (AssertionError, KeyError) as exc:
        assert expected.lower() in str(exc).lower() or not str(exc), (
            f"expected failure containing {expected!r}, got {exc!r}"
        )
        return
    raise AssertionError(f"invalid profile unexpectedly passed: {expected}")


def test_profile_and_schema_are_fail_closed() -> None:
    profile = load(PROFILE)
    schema = load(SCHEMA)
    validate_profile(profile)
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["$id"] == profile["schema_path"]
    assert schema["additionalProperties"] is False
    assert schema["properties"]["schema_version"]["const"].endswith("/v3")


def test_layers_are_independent_and_windows_uses_wsl_only_as_backend() -> None:
    profile = load(PROFILE)
    architecture = profile["architecture"]
    assert architecture["terminal"]["role"] == "terminal-host"
    assert architecture["workspace"]["multiplexer"] == "tmux"
    assert architecture["default_backends"]["windows"] == "windows-wsl"
    assert by_id(architecture["fallback_profiles"])["windows-powershell"]["multiplexer"] == "none"


def test_agent_readiness_is_domain_scoped() -> None:
    switchboard = load(PROFILE)["agent_switchboard"]
    assert switchboard["readiness_scope"] == "per-execution-domain"
    assert switchboard["windows_command_presence_satisfies_wsl_readiness"] is False
    domains = {item["execution_domain"] for item in load(PROFILE)["architecture"]["tmux_backends"]}
    assert domains == {"windows-wsl", "linux-native"}


def test_negative_contract_invariants() -> None:
    cases = [
        (lambda p: p.__setitem__("schema_version", "sas-developer-workstation-profile/v2"), "v3"),
        (lambda p: p["architecture"]["terminal"].__setitem__("provider", "powershell"), "wezterm"),
        (lambda p: p["architecture"]["workspace"].__setitem__("multiplexer", "none"), "tmux"),
        (lambda p: p["architecture"]["default_backends"].__setitem__("windows", "windows-powershell"), "windows-wsl"),
        (lambda p: p["architecture"]["tmux_backends"][0].__setitem__("tmux_capable", False), "true"),
        (lambda p: p["architecture"]["tmux_backends"][0].__setitem__("execution_domain", "windows-native"), "windows-native"),
        (lambda p: p["architecture"]["tmux_backends"][0]["distro_selector"].__setitem__("mode", "default"), "detected-non-docker"),
        (lambda p: p["architecture"]["tmux_backends"][0]["distro_selector"].__setitem__("excluded_names", []), "docker-desktop"),
        (lambda p: p["architecture"]["tmux_backends"][1].__setitem__("kind", "wsl"), "native-linux"),
        (lambda p: p["architecture"]["fallback_profiles"][0].__setitem__("multiplexer", "tmux"), "none"),
        (lambda p: p["agent_switchboard"].__setitem__("readiness_scope", "host"), "per-execution-domain"),
        (lambda p: p["agent_switchboard"].__setitem__("windows_command_presence_satisfies_wsl_readiness", True), "false"),
        (lambda p: p["platform_support"]["supported"].append("macos"), "windows"),
        (lambda p: p["project"].__setitem__("repo_path", "~/dev/SysAdminSuite"), ""),
    ]
    for mutator, expected in cases:
        assert_invalid(mutator, expected)


def test_schema_rejects_cross_layer_contradictions_when_available() -> None:
    try:
        import jsonschema
    except ImportError:
        return
    schema = load(SCHEMA)
    jsonschema.validate(load(PROFILE), schema)
    mutations = []
    for path, value in [
        (("architecture", "tmux_backends", 0, "tmux_capable"), False),
        (("architecture", "tmux_backends", 0, "execution_domain"), "windows-native"),
        (("architecture", "fallback_profiles", 0, "multiplexer"), "tmux"),
        (("agent_switchboard", "windows_command_presence_satisfies_wsl_readiness"), True),
    ]:
        profile = copy.deepcopy(load(PROFILE))
        target = profile
        for segment in path[:-1]:
            target = target[segment]
        target[path[-1]] = value
        mutations.append(profile)
    for profile in mutations:
        try:
            jsonschema.validate(profile, schema)
        except jsonschema.ValidationError:
            continue
        raise AssertionError("schema accepted a fail-closed invariant violation")


def test_contract_is_sanitized_discoverable_and_registered() -> None:
    profile_text = read(PROFILE)
    assert not re.search(r"[A-Za-z]:\\\\", profile_text)
    assert "/mnt/c/Users/" not in profile_text
    assert "Cheex" not in profile_text
    for path in (
        "schemas/harness/developer-workstation-profile.schema.json",
        "Config/developer-workstation-profile.sample.json",
        "docs/DEVELOPER_WORKSTATION_PR_STACK.md",
    ):
        assert path in read(MAP) or path in read(DOC)
    assert "python3 Tests/survey/test_developer_workstation_profile_contracts.py" in read(RUNNER)


def test_pr_stack_ledger_quarantines_old_assumptions() -> None:
    ledger = read(LEDGER)
    for number in (199, 201, 202, 203, 204):
        assert f"#{number}" in ledger
    assert "BLOCKED" in ledger
    assert "SUPERSEDE" in ledger
    assert "PowerShell-primary" in ledger


def main() -> None:
    tests = [
        test_profile_and_schema_are_fail_closed,
        test_layers_are_independent_and_windows_uses_wsl_only_as_backend,
        test_agent_readiness_is_domain_scoped,
        test_negative_contract_invariants,
        test_schema_rejects_cross_layer_contradictions_when_available,
        test_contract_is_sanitized_discoverable_and_registered,
        test_pr_stack_ledger_quarantines_old_assumptions,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} persistent developer workstation profile contracts")


if __name__ == "__main__":
    main()
