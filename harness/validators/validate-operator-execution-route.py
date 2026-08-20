#!/usr/bin/env python3
"""Validate operator execution-location and front-door harness contracts."""
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

try:
    import jsonschema  # type: ignore
except ImportError:  # Local hooks remain dependency-free; dedicated CI installs jsonschema.
    jsonschema = None

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
POLICY_KEYS = {
    "resolve_execution_location_before_operator_command",
    "registered_front_door_overrides_inner_command_for_operator",
    "same_turn_execute_when_capability_exists",
    "otherwise_emit_one_route_and_run_command",
    "do_not_assume_current_directory",
    "do_not_require_operator_to_retype_repo_path",
    "propagate_child_exit_code",
    "preserve_operator_shell_on_child_failure",
    "fail_closed_when_location_or_entrypoint_is_unproven",
}
ROUTE_KEYS = {
    "id", "command_id", "platform", "required_network", "repository_freshness_dependency",
    "path_resolution", "operator_front_door", "operator_entrypoint", "operator_helper",
    "inner_product_command", "target_placeholder", "target_encoding", "target_validation_pattern",
    "operator_command_template", "success_artifact", "latest_pointer", "proof_ceiling",
}
PATH_KEYS = {"strategy_order", "installed_sas_probe", "cache_path", "required_files", "fail_closed"}


def read(path: Path) -> str:
    assert path.is_file(), f"missing operator-execution component: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def one(items: list[dict], key: str, value: str) -> dict:
    matches = [item for item in items if str(item.get(key, "")) == value]
    assert len(matches) == 1, f"expected one {key}={value}, found {len(matches)}"
    return matches[0]


def exact_keys(value: dict, expected: set[str], label: str) -> None:
    actual = set(value)
    assert actual == expected, f"{label} key drift; missing={sorted(expected-actual)} unknown={sorted(actual-expected)}"


def tracked(path: Path) -> bool:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", path.relative_to(ROOT).as_posix()],
        text=True, capture_output=True, check=False,
    )
    return result.returncode == 0


def tracked_repo_file(relative: str, label: str) -> Path:
    rel = Path(relative)
    assert not rel.is_absolute(), f"{label} must be repository-relative: {relative}"
    candidate = (ROOT / rel).resolve()
    try:
        candidate.relative_to(ROOT.resolve())
    except ValueError as exc:
        raise AssertionError(f"{label} escapes repository root: {relative}") from exc
    assert candidate.is_file(), f"{label} is missing: {relative}"
    assert tracked(candidate), f"{label} is not tracked: {relative}"
    return candidate


def test_components_exist_and_are_tracked() -> None:
    for path in COMPONENTS:
        assert path.is_file(), f"missing operator-execution component: {path.relative_to(ROOT)}"
        assert tracked(path), f"operator-execution component is not tracked: {path.relative_to(ROOT)}"


def test_registry_shape_and_schema() -> None:
    data = load(REGISTRY)
    schema = load(SCHEMA)
    exact_keys(data, {"schema_version", "repository", "policy", "routes"}, "route registry")
    assert data["schema_version"] == "sas-operator-execution-route-registry/v1"
    assert data["repository"] == "EndeavorEverlasting/SysAdminSuite"
    exact_keys(data["policy"], POLICY_KEYS, "route policy")
    assert all(data["policy"][key] is True for key in POLICY_KEYS)
    assert isinstance(data["routes"], list) and data["routes"], "routes must be a non-empty array"
    assert schema["$schema"].endswith("draft/2020-12/schema")
    assert schema["properties"]["schema_version"]["const"] == data["schema_version"]
    if jsonschema is not None:
        jsonschema.Draft202012Validator.check_schema(schema)
        jsonschema.Draft202012Validator(schema).validate(data)
        print("PASS: declared Draft 2020-12 operator route schema")
    else:
        print("PASS: dependency-free operator route shape (jsonschema unavailable locally)")


def test_autologon_route_contract() -> None:
    route = one(load(REGISTRY)["routes"], "command_id", "autologon-remote")
    exact_keys(route, ROUTE_KEYS, "autologon route")
    exact_keys(route["path_resolution"], PATH_KEYS, "autologon path resolution")
    assert route["id"] == "autologon-remote-crash-safe"
    assert route["platform"] == "windows-powershell"
    assert route["required_network"] == "PROTECTED_NORTHWELL"
    assert route["operator_front_door"] == "Run-AutoLogonCrashSafe.cmd HOST"
    assert route["operator_entrypoint"] == "Run-AutoLogonCrashSafe.cmd"
    assert route["operator_helper"] == "harness/scripts/Invoke-SasOperatorExecutionRoute.ps1"
    assert route["inner_product_command"] == "sas autologon Remote HOST"
    assert route["target_placeholder"] == "HOST_B64"
    assert route["target_encoding"] == "utf8-base64"

    pattern = re.compile(route["target_validation_pattern"])
    assert pattern.fullmatch("wpj075opr046.nslijhs.net")
    assert not pattern.fullmatch("server01'; Write-Output INJECTED; '")
    tracked_repo_file(route["repository_freshness_dependency"], "freshness dependency")

    path = route["path_resolution"]
    assert path["strategy_order"] == ["installed-sas-repo", "cached-repo-root"]
    assert path["installed_sas_probe"] == "sas repo"
    assert path["cache_path"] == r"%LOCALAPPDATA%\SysAdminSuite\repo-root.txt"
    assert path["fail_closed"] is True
    expected_files = {
        "Run-AutoLogonCrashSafe.cmd",
        "scripts/Invoke-SasAutoLogonCrashSafeFieldRun.ps1",
        "scripts/Invoke-SasAutoLogonFieldDeployment.ps1",
        "harness/scripts/Invoke-SasOperatorExecutionRoute.ps1",
    }
    assert set(path["required_files"]) == expected_files
    assert len(path["required_files"]) == len(set(path["required_files"]))
    for relative in path["required_files"]:
        tracked_repo_file(relative, "registered route dependency")
    assert route["operator_entrypoint"] in path["required_files"]
    assert route["operator_helper"] in path["required_files"]

    template = route["operator_command_template"]
    # Reject a nested child `powershell.exe ... -Command` source boundary without confusing
    # the legitimate `Get-Command sas` cmdlet text with a command-line -Command argument.
    assert "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command" not in template
    assert template.count("HOST_B64") == 1
    assert "'HOST'" not in template
    for marker in (
        "Get-Command sas", "sas repo", "repo-root.txt", "operator-execution-route-registry.json",
        "$route.path_resolution.required_files", "Required operator route file missing:",
        "$route.operator_helper", "Set-Location -LiteralPath $repo",
        "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $helper 'HOST_B64'",
        "$previousPreference=$ErrorActionPreference", "$ErrorActionPreference='Continue'",
        "$code=[int]$LASTEXITCODE", "$global:LASTEXITCODE=$code", "Operator route failed with exit code",
    ):
        assert marker in template, f"route template missing: {marker}"
    assert "exit $LASTEXITCODE" not in template
    assert "sas autologon Remote HOST" not in template

    helper = read(HELPER)
    for marker in (
        "FromBase64String($TargetBase64)", "SAS_OPERATOR_ROUTE_TARGET_ENCODING_INVALID",
        "target_validation_pattern", "SAS_OPERATOR_ROUTE_TARGET_INVALID", "path_resolution.required_files",
        "operator_entrypoint", "& $launcher $target", "exit [int]$LASTEXITCODE",
    ):
        assert marker in helper, f"route helper missing: {marker}"


def test_central_registration() -> None:
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
        item = components.get(component_id)
        assert item, f"operational manifest missing: {component_id}"
        assert item["kind"] == kind and item["path"] == path
        assert item["required"] is True and item["tracked"] is True
        assert item["validation"] == "python harness/validators/validate-operator-execution-route.py"
    assert "python harness/validators/validate-operator-execution-route.py" in manifest["validation_commands"]
    kinds = load(MANIFEST_SCHEMA)["properties"]["components"]["items"]["properties"]["kind"]["enum"]
    assert "execution_route_registry" in kinds

    entry = one(load(VALIDATORS)["validators"], "id", "operator-execution-route-contracts")
    assert entry["blocking"] is True
    assert entry["command"] == "python harness/validators/validate-operator-execution-route.py"
    scope = " ".join(entry["scope"])
    for marker in ("operator-execution-route-registry", "fresh-agent-intake", "Run-AutoLogonCrashSafe.cmd", ".githooks"):
        assert marker in scope, f"validator registry scope missing: {marker}"


def test_existing_authorities_align() -> None:
    command = one(load(COMMANDS)["commands"], "id", "autologon-remote")
    assert command["command"] == "sas autologon Remote HOST"
    assert command["mutation"] == "authorized_target_mutation" and command["network"] is True
    front = one(load(TERMINAL)["front_doors"], "command_id", "autologon-remote")
    assert front["operator_command"] == "Run-AutoLogonCrashSafe.cmd HOST"
    assert front["operator_entrypoint"] == "Run-AutoLogonCrashSafe.cmd"
    assert front["latest_pointer"] == r"%LOCALAPPDATA%/SysAdminSuite/last-autologon-field-run.json"

    launcher = read(LAUNCHER)
    for marker in (
        r"%~dp0scripts\Invoke-SasAutoLogonCrashSafeFieldRun.ps1", '-RepositoryRoot "%~dp0"',
        r"%%LOCALAPPDATA%%\SysAdminSuite\field-runs\autologon", "pause", "exit /b",
    ):
        assert marker in launcher, f"crash-safe launcher drifted: {marker}"


def test_workflow_skill_report_and_intake() -> None:
    required_by_file = {
        FRESH_AGENT: (
            "harness/api/operator-execution-route-registry.json", "harness/workflows/operator-execution-route.yaml",
            "harness/skills/operator-execution-route/SKILL.md", "resolve executable location before operator command handoff",
            "do not treat harness-command-registry command text as operator handoff until execution-route lookup is complete",
            "python harness/validators/validate-operator-execution-route.py", "one copy-paste route-and-run command",
        ),
        WORKFLOW: (
            "workflow_id: operator-execution-route", "verify repository_freshness_dependency resolves to a tracked file",
            "never assume the current shell is already inside the repository", "target_validation_pattern", "target_encoding",
            "never interpolate the raw explicit_target into PowerShell command source", "powershell.exe -File",
            "never return only sas autologon Remote HOST",
        ),
        SKILL: (
            "## Trigger", "## Procedure", "## AutoLogon rule", "Run-AutoLogonCrashSafe.cmd HOST",
            "sas autologon Remote HOST", "target_validation_pattern", "target_encoding", "powershell.exe -File",
            "one copy-paste route-and-run command", "## Expected outputs", "## Proof ceiling",
        ),
        MAP: (
            "Operator Execution Route Map", "operator-execution-route-registry.json", "Run-AutoLogonCrashSafe.cmd HOST",
            "Invoke-SasOperatorExecutionRoute.ps1", "UTF-8 Base64", "Known trap this prevents",
        ),
        REPORT: (
            "## Working", "## Repaired boundary", "## Missing / not proven", "## Current AutoLogon route",
            "Run-AutoLogonCrashSafe.cmd HOST", "UTF-8 Base64", "operator shell",
        ),
    }
    for path, markers in required_by_file.items():
        text = read(path)
        for marker in markers:
            assert marker in text, f"{path.relative_to(ROOT)} missing: {marker}"


def test_hooks_and_ci() -> None:
    assert "validate-operator-execution-route.py" in read(PRE_COMMIT)
    pre_push = read(PRE_PUSH)
    for marker in (
        "validate_freshness_tip()", "validate_pushed_tip()", 'git worktree add --detach --quiet "$wt" "$commit"',
        'git cat-file -e "$commit:harness/validators/validate-operator-execution-route.py"',
        "python3 harness/validators/validate-operator-execution-route.py", "dirty local files cannot mask failures",
    ):
        assert marker in pre_push, f"pre-push pushed-tip route validation missing: {marker}"
    prefix = pre_push.split("validate_pushed_tip()", 1)[0]
    assert "python3 harness/validators/validate-operator-execution-route.py" not in prefix

    ci = read(CI)
    for marker in (
        "Operator Execution Route Harness", "python -m pip install jsonschema",
        "repository-freshness-before-launch.yaml", "Invoke-SasAutoLogonCrashSafeFieldRun.ps1",
        "Invoke-SasAutoLogonFieldDeployment.ps1", "Invoke-SasOperatorExecutionRoute.ps1",
        "OperatorExecutionRouteHarness.Tests.ps1", "fetch-depth: 0",
        "python harness/validators/validate-operator-execution-route.py", "validate-harness-registries.py",
        "test_operational_harness_completeness_contracts.py", "git diff --check", "runs-on: windows-latest",
    ):
        assert marker in ci, f"operator execution CI missing: {marker}"


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: operator execution route harness contracts ({len(tests)} groups)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
