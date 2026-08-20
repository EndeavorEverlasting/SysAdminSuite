#!/usr/bin/env python3
"""Validate operator execution-location and front-door harness contracts."""
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "harness/api/operator-execution-route-registry.json"
SCHEMA = ROOT / "schemas/harness/operator-execution-route-registry.schema.json"
MANIFEST = ROOT / "harness/api/operational-harness-manifest.json"
MANIFEST_SCHEMA = ROOT / "schemas/harness/operational-harness-manifest.schema.json"
VALIDATORS = ROOT / "harness/api/harness-validator-registry.json"
WORKFLOW = ROOT / "harness/workflows/operator-execution-route.yaml"
SKILL = ROOT / "harness/skills/operator-execution-route/SKILL.md"
MAP = ROOT / "harness/maps/OPERATOR_EXECUTION_ROUTE_MAP.md"
REPORT = ROOT / "harness/reports/OPERATOR_EXECUTION_ROUTE_STATUS.md"
FRESH_AGENT = ROOT / "harness/workflows/fresh-agent-intake.yaml"
COMMANDS = ROOT / "harness/api/harness-command-registry.json"
TERMINAL = ROOT / "harness/api/terminal-evidence-survival-registry.json"
LAUNCHER = ROOT / "Run-AutoLogonCrashSafe.cmd"
HELPER = ROOT / "harness/scripts/Invoke-SasOperatorExecutionRoute.ps1"
WINDOWS_TEST = ROOT / "Tests/PowerShell/OperatorExecutionRouteHarness.Tests.ps1"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"
CI = ROOT / ".github/workflows/operator-execution-route-harness.yml"

COMPONENTS = (
    REGISTRY, SCHEMA, MANIFEST, MANIFEST_SCHEMA, VALIDATORS, WORKFLOW, SKILL, MAP, REPORT,
    FRESH_AGENT, COMMANDS, TERMINAL, LAUNCHER, HELPER, WINDOWS_TEST, PRE_COMMIT, PRE_PUSH, CI,
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


def validate_schema(instance: dict, schema: dict, label: str) -> None:
    Draft202012Validator.check_schema(schema)
    errors = sorted(
        Draft202012Validator(schema).iter_errors(instance),
        key=lambda error: [str(part) for part in error.absolute_path],
    )
    if errors:
        details = []
        for error in errors:
            location = "/".join(str(part) for part in error.absolute_path) or "<root>"
            details.append(f"{location}: {error.message}")
        raise AssertionError(f"{label} schema validation failed: {'; '.join(details)}")


def resolve_tracked_repo_path(relative: str, label: str) -> Path:
    rel = Path(relative)
    assert not rel.is_absolute(), f"{label} must be repository-relative: {relative}"
    candidate = (ROOT / rel).resolve()
    root = ROOT.resolve()
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise AssertionError(f"{label} escapes repository root: {relative}") from exc
    assert candidate.is_file(), f"{label} is missing: {relative}"
    assert tracked(candidate), f"{label} is not tracked: {relative}"
    return candidate


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
    validate_schema(registry, schema, "operator execution route registry")

    policy = registry["policy"]
    for key in (
        "resolve_execution_location_before_operator_command",
        "registered_front_door_overrides_inner_command_for_operator",
        "same_turn_execute_when_capability_exists",
        "otherwise_emit_one_route_and_run_command",
        "do_not_assume_current_directory",
        "do_not_require_operator_to_retype_repo_path",
        "propagate_child_exit_code",
        "preserve_operator_shell_on_child_failure",
        "fail_closed_when_location_or_entrypoint_is_unproven",
    ):
        assert policy[key] is True, f"operator execution policy disabled: {key}"

    route = one(registry["routes"], "command_id", "autologon-remote")
    assert route["id"] == "autologon-remote-crash-safe"
    assert route["operator_front_door"] == "Run-AutoLogonCrashSafe.cmd HOST"
    assert route["operator_entrypoint"] == "Run-AutoLogonCrashSafe.cmd"
    assert route["operator_helper"] == "harness/scripts/Invoke-SasOperatorExecutionRoute.ps1"
    assert route["inner_product_command"] == "sas autologon Remote HOST"
    assert route["target_placeholder"] == "HOST_B64"
    assert route["target_encoding"] == "utf8-base64"
    target_pattern = re.compile(route["target_validation_pattern"])
    assert target_pattern.fullmatch("wpj075opr046.nslijhs.net")
    assert not target_pattern.fullmatch("server01'; Write-Output INJECTED; '")

    freshness = route["repository_freshness_dependency"]
    resolve_tracked_repo_path(freshness, "repository freshness dependency")

    assert route["path_resolution"]["strategy_order"] == ["installed-sas-repo", "cached-repo-root"]
    assert route["path_resolution"]["installed_sas_probe"] == "sas repo"
    assert route["path_resolution"]["cache_path"] == r"%LOCALAPPDATA%\SysAdminSuite\repo-root.txt"
    assert route["path_resolution"]["fail_closed"] is True
    assert route["required_network"] == "PROTECTED_NORTHWELL"

    required_files = route["path_resolution"]["required_files"]
    for required in (
        "Run-AutoLogonCrashSafe.cmd",
        "scripts/Invoke-SasAutoLogonCrashSafeFieldRun.ps1",
        "scripts/Invoke-SasAutoLogonFieldDeployment.ps1",
        "harness/scripts/Invoke-SasOperatorExecutionRoute.ps1",
    ):
        assert required in required_files
        resolve_tracked_repo_path(required, "registered route dependency")
    assert route["operator_helper"] in required_files
    assert route["operator_entrypoint"] in required_files

    template = route["operator_command_template"]
    assert "-Command" not in template, "route template embeds a child PowerShell source command"
    assert template.count(route["target_placeholder"]) == 1, "route target placeholder must appear exactly once"
    assert "'HOST'" not in template, "route template interpolates the raw target placeholder"
    for marker in (
        "Get-Command sas",
        "sas repo",
        "repo-root.txt",
        "operator-execution-route-registry.json",
        "$route.path_resolution.required_files",
        "foreach($relative in",
        "Required operator route file missing:",
        "$route.operator_helper",
        "Set-Location -LiteralPath $repo",
        "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $helper 'HOST_B64'",
        "$code=[int]$LASTEXITCODE",
        "$global:LASTEXITCODE=$code",
        "Operator route failed with exit code",
    ):
        assert marker in template, f"route-and-run template missing: {marker}"
    assert "exit $LASTEXITCODE" not in template, "operator route closes the caller shell to propagate child failure"
    assert "sas autologon Remote HOST" not in template, "operator template bypasses crash-safe front door"

    helper = read(HELPER)
    for marker in (
        "FromBase64String($TargetBase64)",
        "target_validation_pattern",
        "path_resolution.required_files",
        "operator_entrypoint",
        "& $launcher $target",
        "exit [int]$LASTEXITCODE",
    ):
        assert marker in helper, f"operator route helper missing: {marker}"


def test_central_harness_registration() -> None:
    manifest = load(MANIFEST)
    components = {item["id"]: item for item in manifest["components"]}
    expected = {
        "operator-execution-route-workflow": ("workflow", "harness/workflows/operator-execution-route.yaml"),
        "operator-execution-route-registry": ("execution_route_registry", "harness/api/operator-execution-route-registry.json"),
        "operator-execution-route-schema": ("schema", "schemas/harness/operator-execution-route-registry.schema.json"),
        "operator-execution-route-validator": ("validator", "harness/validators/validate-operator-execution-route.py"),
        "operator-execution-route-skill": ("skill", "harness/skills/operator-execution-route/SKILL.md"),
        "operator-execution-route-map": ("codebase_map", "harness/maps/OPERATOR_EXECUTION_ROUTE_MAP.md"),
        "operator-execution-route-report": ("operator_report", "harness/reports/OPERATOR_EXECUTION_ROUTE_STATUS.md"),
        "operator-execution-route-ci": ("ci", ".github/workflows/operator-execution-route-harness.yml"),
    }
    for component_id, (kind, path) in expected.items():
        assert component_id in components, f"operational manifest missing: {component_id}"
        component = components[component_id]
        assert component["kind"] == kind
        assert component["path"] == path
        assert component["required"] is True and component["tracked"] is True
        assert component["validation"] == "python harness/validators/validate-operator-execution-route.py"
    assert "python harness/validators/validate-operator-execution-route.py" in manifest["validation_commands"]

    manifest_schema = load(MANIFEST_SCHEMA)
    kind_enum = manifest_schema["properties"]["components"]["items"]["properties"]["kind"]["enum"]
    assert "execution_route_registry" in kind_enum

    validator_registry = load(VALIDATORS)
    validator = one(validator_registry["validators"], "id", "operator-execution-route-contracts")
    assert validator["blocking"] is True
    assert validator["command"] == "python harness/validators/validate-operator-execution-route.py"
    for path in (
        "harness/api/operator-execution-route-registry.json",
        "harness/api/operational-harness-manifest.json",
        "harness/workflows/operator-execution-route.yaml",
        "harness/workflows/fresh-agent-intake.yaml",
        "Run-AutoLogonCrashSafe.cmd",
        ".githooks/**",
        ".github/workflows/operator-execution-route-harness.yml",
    ):
        assert path in validator["scope"], f"validator registry scope missing: {path}"


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
        r"%%LOCALAPPDATA%%\SysAdminSuite\field-runs\autologon",
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
        "verify repository_freshness_dependency resolves to a tracked file",
        "never assume the current shell is already inside the repository",
        "installed sas repo command",
        "repo-root.txt",
        "target_validation_pattern",
        "target_encoding",
        "never interpolate the raw explicit_target into PowerShell command source",
        "powershell.exe -File",
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
        "target_validation_pattern",
        "target_encoding",
        "powershell.exe -File",
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
    pre_commit = read(PRE_COMMIT)
    assert "validate-operator-execution-route.py" in pre_commit, "pre-commit missing operator route validator"

    pre_push = read(PRE_PUSH)
    for marker in (
        "validate_pushed_tip",
        'git worktree add --detach --quiet "$wt" "$commit"',
        'git cat-file -e "$commit:harness/validators/validate-operator-execution-route.py"',
        "python3 harness/validators/validate-operator-execution-route.py",
    ):
        assert marker in pre_push, f"pre-push pushed-tip route validation missing: {marker}"
    pre_push_prefix = pre_push.split("validate_pushed_tip()", 1)[0]
    assert "python3 harness/validators/validate-operator-execution-route.py" not in pre_push_prefix, (
        "pre-push validates operator route from mutable working tree before pushed-tip isolation"
    )

    ci = read(CI)
    for marker in (
        "Operator Execution Route Harness",
        "harness/api/operational-harness-manifest.json",
        "harness/api/harness-validator-registry.json",
        "schemas/harness/operational-harness-manifest.schema.json",
        "harness/workflows/repository-freshness-before-launch.yaml",
        "scripts/Invoke-SasAutoLogonCrashSafeFieldRun.ps1",
        "scripts/Invoke-SasAutoLogonFieldDeployment.ps1",
        "harness/scripts/Invoke-SasOperatorExecutionRoute.ps1",
        "Tests/PowerShell/OperatorExecutionRouteHarness.Tests.ps1",
        "fetch-depth: 0",
        "python harness/validators/validate-operator-execution-route.py",
        "python harness/validators/validate-harness-registries.py",
        "python Tests/survey/test_operational_harness_completeness_contracts.py",
        "git diff --check",
        "runs-on: windows-latest",
        "Execute route-and-run template under Windows PowerShell 5.1",
    ):
        assert marker in ci, f"operator execution CI missing: {marker}"


def main() -> int:
    test_components_exist_and_are_tracked()
    test_registry_and_schema()
    test_central_harness_registration()
    test_command_and_terminal_authorities_align()
    test_launcher_is_location_independent_and_crash_safe()
    test_fresh_agent_workflow_requires_execution_route()
    test_workflow_skill_map_and_report()
    test_hooks_and_ci()
    print("PASS: operator execution route harness contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
