#!/usr/bin/env python3
"""Validate operator execution-location and front-door harness contracts."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "harness/api/operator-execution-route-registry.json"
SCHEMA = ROOT / "schemas/harness/operator-execution-route-registry.schema.json"
WORKFLOW = ROOT / "harness/workflows/operator-execution-route.yaml"
SKILL = ROOT / "harness/skills/operator-execution-route/SKILL.md"
MAP = ROOT / "harness/maps/OPERATOR_EXECUTION_ROUTE_MAP.md"
REPORT = ROOT / "harness/reports/OPERATOR_EXECUTION_ROUTE_STATUS.md"
FRESH_AGENT = ROOT / "harness/workflows/fresh-agent-intake.yaml"
COMMANDS = ROOT / "harness/api/harness-command-registry.json"
TERMINAL = ROOT / "harness/api/terminal-evidence-survival-registry.json"
LAUNCHER = ROOT / "Run-AutoLogonCrashSafe.cmd"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"
CI = ROOT / ".github/workflows/operator-execution-route-harness.yml"

COMPONENTS = (
    REGISTRY, SCHEMA, WORKFLOW, SKILL, MAP, REPORT, FRESH_AGENT,
    COMMANDS, TERMINAL, LAUNCHER, PRE_COMMIT, PRE_PUSH, CI,
)


def read(path: Path) -> str:
    assert path.is_file(), f"missing operator-execution component: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def tracked(path: Path) -> bool:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", path.relative_to(ROOT).as_posix()],
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def one(items: list[dict], key: str, value: str) -> dict:
    matches = [item for item in items if str(item.get(key, "")) == value]
    assert len(matches) == 1, f"expected one {key}={value}, found {len(matches)}"
    return matches[0]


def test_components_exist_and_are_tracked() -> None:
    for path in COMPONENTS:
        assert path.is_file(), f"missing operator-execution component: {path.relative_to(ROOT)}"
        assert tracked(path), f"operator-execution component is not tracked: {path.relative_to(ROOT)}"


def test_registry_and_schema() -> None:
    registry = load(REGISTRY)
    schema = load(SCHEMA)
    assert registry["schema_version"] == "sas-operator-execution-route-registry/v1"
    assert registry["repository"] == "EndeavorEverlasting/SysAdminSuite"
    assert schema["$schema"].endswith("draft/2020-12/schema")
    assert schema["properties"]["schema_version"]["const"] == registry["schema_version"]

    policy = registry["policy"]
    for key in (
        "resolve_execution_location_before_operator_command",
        "registered_front_door_overrides_inner_command_for_operator",
        "same_turn_execute_when_capability_exists",
        "otherwise_emit_one_route_and_run_command",
        "do_not_assume_current_directory",
        "do_not_require_operator_to_retype_repo_path",
        "propagate_child_exit_code",
        "fail_closed_when_location_or_entrypoint_is_unproven",
    ):
        assert policy[key] is True, f"operator execution policy disabled: {key}"

    route = one(registry["routes"], "command_id", "autologon-remote")
    assert route["id"] == "autologon-remote-crash-safe"
    assert route["operator_front_door"] == "Run-AutoLogonCrashSafe.cmd HOST"
    assert route["inner_product_command"] == "sas autologon Remote HOST"
    assert route["path_resolution"]["strategy_order"] == ["installed-sas-repo", "cached-repo-root"]
    assert route["path_resolution"]["installed_sas_probe"] == "sas repo"
    assert route["path_resolution"]["cache_path"] == r"%LOCALAPPDATA%\SysAdminSuite\repo-root.txt"
    assert route["path_resolution"]["fail_closed"] is True
    assert route["required_network"] == "PROTECTED_NORTHWELL"
    assert route["repository_freshness_dependency"] == "harness/workflows/repository-freshness-before-launch.yaml"

    for required in (
        "Run-AutoLogonCrashSafe.cmd",
        "scripts/Invoke-SasAutoLogonCrashSafeFieldRun.ps1",
        "scripts/Invoke-SasAutoLogonFieldDeployment.ps1",
    ):
        assert required in route["path_resolution"]["required_files"]
        assert (ROOT / required).is_file(), f"registered required file missing: {required}"

    template = route["operator_command_template"]
    for marker in (
        "Get-Command sas",
        "sas repo",
        "repo-root.txt",
        "Run-AutoLogonCrashSafe.cmd",
        "Set-Location -LiteralPath $repo",
        "& $launcher 'HOST'",
        "exit $LASTEXITCODE",
    ):
        assert marker in template, f"route-and-run template missing: {marker}"
    assert "sas autologon Remote HOST" not in template, "operator template bypasses crash-safe front door"


def test_command_and_terminal_authorities_align() -> None:
    commands = load(COMMANDS)["commands"]
    command = one(commands, "id", "autologon-remote")
    assert command["command"] == "sas autologon Remote HOST"
    assert command["mutation"] == "authorized_target_mutation"
    assert command["network"] is True

    terminal = load(TERMINAL)
    front = one(terminal["front_doors"], "command_id", "autologon-remote")
    assert front["operator_command"] == "Run-AutoLogonCrashSafe.cmd HOST"
    assert front["operator_entrypoint"] == "Run-AutoLogonCrashSafe.cmd"
    assert front["latest_pointer"] == r"%LOCALAPPDATA%/SysAdminSuite/last-autologon-field-run.json"


def test_launcher_is_location_independent_and_crash_safe() -> None:
    launcher = read(LAUNCHER)
    for marker in (
        r"%~dp0scripts\Invoke-SasAutoLogonCrashSafeFieldRun.ps1",
        '-RepositoryRoot "%~dp0"',
        r"%LOCALAPPDATA%\SysAdminSuite\field-runs\autologon",
        "pause",
        "exit /b",
    ):
        assert marker in launcher, f"crash-safe launcher drifted: {marker}"


def test_fresh_agent_workflow_requires_execution_route() -> None:
    workflow = read(FRESH_AGENT)
    for marker in (
        "harness/api/operator-execution-route-registry.json",
        "harness/workflows/operator-execution-route.yaml",
        "harness/skills/operator-execution-route/SKILL.md",
        "resolve executable location before operator command handoff",
        "do not treat harness-command-registry command text as operator handoff until execution-route lookup is complete",
        "python harness/validators/validate-operator-execution-route.py",
        "one copy-paste route-and-run command",
    ):
        assert marker in workflow, f"fresh-agent execution-route wiring missing: {marker}"


def test_workflow_skill_map_and_report() -> None:
    workflow = read(WORKFLOW)
    for marker in (
        "workflow_id: operator-execution-route",
        "never assume the current shell is already inside the repository",
        "installed sas repo command",
        "repo-root.txt",
        "Set-Location",
        "same turn",
        "never return only sas autologon Remote HOST",
    ):
        assert marker in workflow, f"operator execution workflow missing: {marker}"

    skill = read(SKILL)
    for marker in (
        "## Trigger",
        "## Required inputs",
        "## Procedure",
        "## AutoLogon rule",
        "Run-AutoLogonCrashSafe.cmd HOST",
        "sas autologon Remote HOST",
        "one copy-paste route-and-run command",
        "## Expected outputs",
        "## Proof ceiling",
    ):
        assert marker in skill, f"operator execution skill missing: {marker}"

    map_text = read(MAP)
    for marker in (
        "Operator Execution Route Map",
        "harness/api/operator-execution-route-registry.json",
        "Run-AutoLogonCrashSafe.cmd HOST",
        "Set-Location",
        "Known trap this prevents",
    ):
        assert marker in map_text, f"operator execution map missing: {marker}"

    report = read(REPORT)
    for marker in (
        "## Working",
        "## Repaired boundary",
        "## Missing / not proven",
        "## Current AutoLogon route",
        "Run-AutoLogonCrashSafe.cmd HOST",
        "repo-root.txt",
    ):
        assert marker in report, f"operator execution report missing: {marker}"


def test_hooks_and_ci() -> None:
    for path in (PRE_COMMIT, PRE_PUSH):
        text = read(path)
        assert "validate-operator-execution-route.py" in text, f"hook missing operator route validator: {path.name}"

    ci = read(CI)
    for marker in (
        "Operator Execution Route Harness",
        "python harness/validators/validate-operator-execution-route.py",
        "python harness/validators/validate-harness-registries.py",
        "python Tests/survey/test_operational_harness_completeness_contracts.py",
        "git diff --check",
    ):
        assert marker in ci, f"operator execution CI missing: {marker}"


def main() -> int:
    test_components_exist_and_are_tracked()
    test_registry_and_schema()
    test_command_and_terminal_authorities_align()
    test_launcher_is_location_independent_and_crash_safe()
    test_fresh_agent_workflow_requires_execution_route()
    test_workflow_skill_map_and_report()
    test_hooks_and_ci()
    print("PASS: operator execution route harness contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
