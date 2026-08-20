#!/usr/bin/env python3
"""Validate operator execution-location and front-door harness contracts."""
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

try:
    import jsonschema  # type: ignore
except ImportError:
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
SAS_LAUNCHER = ROOT / "scripts/SasPortableLauncher.ps1"
SEALED_BOOTSTRAP = ROOT / "Bootstrap-SysAdminSuiteAutoLogon.ps1"
HELPER = ROOT / "harness/scripts/Invoke-SasOperatorExecutionRoute.ps1"
WINDOWS_TEST = ROOT / "Tests/PowerShell/OperatorExecutionRouteHarness.Tests.ps1"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"
CI = ROOT / ".github/workflows/operator-execution-route-harness.yml"

COMPONENTS = (
    REGISTRY, SCHEMA, MANIFEST, MANIFEST_SCHEMA, VALIDATORS, WORKFLOW, SKILL, MAP, REPORT,
    FRESH_AGENT, COMMANDS, TERMINAL, LAUNCHER, SAS_LAUNCHER, SEALED_BOOTSTRAP, HELPER,
    WINDOWS_TEST, PRE_COMMIT, PRE_PUSH, CI,
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


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def read(path: Path) -> str:
    require(path.is_file(), f"missing operator-execution component: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def one(items: list[dict], key: str, value: str) -> dict:
    matches = [item for item in items if str(item.get(key, "")) == value]
    require(len(matches) == 1, f"expected one {key}={value}, found {len(matches)}")
    return matches[0]


def exact_keys(value: dict, expected: set[str], label: str) -> None:
    actual = set(value)
    require(actual == expected, f"{label} key drift; missing={sorted(expected-actual)} unknown={sorted(actual-expected)}")


def tracked(path: Path) -> bool:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", path.relative_to(ROOT).as_posix()],
        text=True, capture_output=True, check=False,
    )
    return result.returncode == 0


def tracked_repo_file(relative: str, label: str) -> Path:
    rel = Path(relative)
    require(not rel.is_absolute(), f"{label} must be repository-relative: {relative}")
    candidate = (ROOT / rel).resolve()
    try:
        candidate.relative_to(ROOT.resolve())
    except ValueError as exc:
        raise AssertionError(f"{label} escapes repository root: {relative}") from exc
    require(candidate.is_file(), f"{label} is missing: {relative}")
    require(tracked(candidate), f"{label} is not tracked: {relative}")
    return candidate


def test_components_exist_and_are_tracked() -> None:
    for path in COMPONENTS:
        require(path.is_file(), f"missing operator-execution component: {path.relative_to(ROOT)}")
        require(tracked(path), f"operator-execution component is not tracked: {path.relative_to(ROOT)}")


def test_registry_shape_and_schema() -> None:
    data = load(REGISTRY)
    schema = load(SCHEMA)
    exact_keys(data, {"schema_version", "repository", "policy", "routes"}, "route registry")
    require(data["schema_version"] == "sas-operator-execution-route-registry/v1", "route registry schema version drift")
    require(data["repository"] == "EndeavorEverlasting/SysAdminSuite", "route registry repository drift")
    exact_keys(data["policy"], POLICY_KEYS, "route policy")
    require(all(data["policy"][key] is True for key in POLICY_KEYS), "route policy must remain fail-closed/route-first")
    require(isinstance(data["routes"], list) and bool(data["routes"]), "routes must be a non-empty array")
    require(schema["$schema"].endswith("draft/2020-12/schema"), "route schema must remain Draft 2020-12")
    require(schema["properties"]["schema_version"]["const"] == data["schema_version"], "schema/registry version mismatch")
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
    require(route["id"] == "autologon-remote-crash-safe", "AutoLogon route id drift")
    require(route["platform"] == "windows-powershell", "AutoLogon route platform drift")
    require(route["required_network"] == "PROTECTED_NORTHWELL", "AutoLogon route network drift")
    require(route["operator_front_door"] == "Run-AutoLogonCrashSafe.cmd HOST", "crash-safe front door drift")
    require(route["operator_entrypoint"] == "Run-AutoLogonCrashSafe.cmd", "crash-safe entrypoint drift")
    require(route["operator_helper"] == "harness/scripts/Invoke-SasOperatorExecutionRoute.ps1", "route helper drift")
    require(route["inner_product_command"] == "sas autologon Remote HOST", "canonical product command drift")
    require(route["target_placeholder"] == "HOST_B64", "target placeholder drift")
    require(route["target_encoding"] == "utf8-base64", "target encoding drift")

    pattern = re.compile(route["target_validation_pattern"])
    require(pattern.fullmatch("wpj075opr046.nslijhs.net") is not None, "valid FQDN rejected by route regex")
    require(pattern.fullmatch("server01'; Write-Output INJECTED; '") is None, "hostile target accepted by route regex")
    tracked_repo_file(route["repository_freshness_dependency"], "freshness dependency")

    path = route["path_resolution"]
    require(path["strategy_order"] == ["installed-sas-repo", "cached-repo-root"], "full-repository fallback strategy drift")
    require(path["installed_sas_probe"] == "sas repo", "sas repo probe drift")
    require(path["cache_path"] == r"%LOCALAPPDATA%\SysAdminSuite\repo-root.txt", "repo-root cache drift")
    require(path["fail_closed"] is True, "fallback path must fail closed")
    expected_files = {
        "Run-AutoLogonCrashSafe.cmd",
        "scripts/Invoke-SasAutoLogonCrashSafeFieldRun.ps1",
        "scripts/Invoke-SasAutoLogonFieldDeployment.ps1",
        "harness/scripts/Invoke-SasOperatorExecutionRoute.ps1",
    }
    require(set(path["required_files"]) == expected_files, "registered fallback dependency drift")
    require(len(path["required_files"]) == len(set(path["required_files"])), "duplicate route dependencies")
    for relative in path["required_files"]:
        tracked_repo_file(relative, "registered route dependency")
    require(route["operator_entrypoint"] in path["required_files"], "entrypoint not registered")
    require(route["operator_helper"] in path["required_files"], "helper not registered")

    template = route["operator_command_template"]
    require("powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command" not in template, "nested -Command payload is forbidden")
    require(template.count("HOST_B64") == 1, "encoded target placeholder must appear exactly once")
    require("'HOST'" not in template, "raw HOST placeholder is forbidden")
    for marker in (
        "$targetBase64='HOST_B64'",
        "FromBase64String($targetBase64)",
        "SAS_OPERATOR_ROUTE_TARGET_ENCODING_INVALID",
        "$target -notmatch $targetPattern",
        "SAS_OPERATOR_ROUTE_TARGET_INVALID",
        "$sasCommand=Get-Command sas",
        "& sas autologon Remote $target",
        "sas repo",
        "repo-root.txt",
        "operator-execution-route-registry.json",
        "$route.path_resolution.required_files",
        "Required operator route file missing:",
        "$route.operator_helper",
        "Set-Location -LiteralPath $repo",
        "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $helper $targetBase64",
        "$previousPreference=$ErrorActionPreference",
        "$ErrorActionPreference='Continue'",
        "$code=[int]$LASTEXITCODE",
        "$global:LASTEXITCODE=$code",
        "Operator route failed with exit code",
    ):
        require(marker in template, f"route template missing: {marker}")
    require("exit $LASTEXITCODE" not in template, "route must preserve parent shell")
    require("sas autologon Remote HOST" not in template, "raw target must never be interpolated")

    helper = read(HELPER)
    for marker in (
        "FromBase64String($TargetBase64)",
        "SAS_OPERATOR_ROUTE_TARGET_ENCODING_INVALID",
        "target_validation_pattern",
        "SAS_OPERATOR_ROUTE_TARGET_INVALID",
        "path_resolution.required_files",
        "operator_entrypoint",
        "& $launcher $target",
        "exit [int]$LASTEXITCODE",
    ):
        require(marker in helper, f"route helper missing: {marker}")


def test_installed_sas_reaches_sealed_crash_safe_path() -> None:
    launcher = read(SAS_LAUNCHER)
    for marker in (
        "Resolve-SasPreparedAutoLogonRuntime",
        "autologon-short-runtime.json",
        "Protected-side Git network I/O: NONE",
        "& $runtime.bootstrap $target $runtime.commit",
    ):
        require(marker in launcher, f"installed sas sealed-runtime contract missing: {marker}")

    bootstrap = read(SEALED_BOOTSTRAP)
    for marker in (
        "C:\\SASAL",
        "Invoke-SasAutoLogonCrashSafeFieldRun.ps1",
        "PRE-STAGED RUNTIME VERIFIED - STARTING CRASH-SAFE AUTOLOGON FIELD TRANSACTION",
        "-ComputerName $ComputerName -RepositoryRoot $RuntimeRoot -ConfirmDeployment",
        "last-autologon-field-run.json",
    ):
        require(marker in bootstrap, f"sealed bootstrap crash-safe contract missing: {marker}")


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
        require(bool(item), f"operational manifest missing: {component_id}")
        require(item["kind"] == kind and item["path"] == path, f"operational manifest drift: {component_id}")
        require(item["required"] is True and item["tracked"] is True, f"component must remain required/tracked: {component_id}")
        require(item["validation"] == "python harness/validators/validate-operator-execution-route.py", f"validator binding drift: {component_id}")
    require("python harness/validators/validate-operator-execution-route.py" in manifest["validation_commands"], "manifest missing route validator")
    kinds = load(MANIFEST_SCHEMA)["properties"]["components"]["items"]["properties"]["kind"]["enum"]
    require("execution_route_registry" in kinds, "manifest schema missing execution_route_registry kind")

    entry = one(load(VALIDATORS)["validators"], "id", "operator-execution-route-contracts")
    require(entry["blocking"] is True, "route validator must remain blocking")
    require(entry["command"] == "python harness/validators/validate-operator-execution-route.py", "validator registry command drift")
    scope = " ".join(entry["scope"])
    for marker in ("operator-execution-route-registry", "fresh-agent-intake", "Run-AutoLogonCrashSafe.cmd", ".githooks"):
        require(marker in scope, f"validator registry scope missing: {marker}")


def test_existing_authorities_align() -> None:
    command = one(load(COMMANDS)["commands"], "id", "autologon-remote")
    require(command["command"] == "sas autologon Remote HOST", "command registry AutoLogon command drift")
    require(command["mutation"] == "authorized_target_mutation" and command["network"] is True, "AutoLogon command authority drift")
    front = one(load(TERMINAL)["front_doors"], "command_id", "autologon-remote")
    require(front["operator_command"] == "Run-AutoLogonCrashSafe.cmd HOST", "terminal evidence front door drift")
    require(front["operator_entrypoint"] == "Run-AutoLogonCrashSafe.cmd", "terminal evidence entrypoint drift")
    require(front["latest_pointer"] == r"%LOCALAPPDATA%/SysAdminSuite/last-autologon-field-run.json", "terminal evidence pointer drift")

    launcher = read(LAUNCHER)
    for marker in (
        r"%~dp0scripts\Invoke-SasAutoLogonCrashSafeFieldRun.ps1",
        '-RepositoryRoot "%~dp0"',
        r"%%LOCALAPPDATA%%\SysAdminSuite\field-runs\autologon",
        "pause",
        "exit /b",
    ):
        require(marker in launcher, f"crash-safe launcher drifted: {marker}")


def test_workflow_skill_report_and_intake() -> None:
    required_by_file = {
        FRESH_AGENT: (
            "harness/api/operator-execution-route-registry.json",
            "harness/workflows/operator-execution-route.yaml",
            "harness/skills/operator-execution-route/SKILL.md",
            "resolve executable location before operator command handoff",
            "do not treat harness-command-registry command text as operator handoff until execution-route lookup is complete",
            "python harness/validators/validate-operator-execution-route.py",
            "one copy-paste route-and-run command",
        ),
        WORKFLOW: (
            "workflow_id: operator-execution-route",
            "verify repository_freshness_dependency resolves to a tracked file",
            "never assume the current shell is already inside the repository",
            "target_validation_pattern",
            "target_encoding",
            "never interpolate the raw explicit_target into PowerShell command source",
            "powershell.exe -File",
            "never return only sas autologon Remote HOST",
            "sealed C:\\SASAL runtime",
        ),
        SKILL: (
            "## Trigger", "## Procedure", "## AutoLogon rule", "Run-AutoLogonCrashSafe.cmd HOST",
            "sas autologon Remote HOST", "target_validation_pattern", "target_encoding", "powershell.exe -File",
            "one copy-paste", "## Expected outputs", "## Proof ceiling", "C:\\SASAL",
        ),
        MAP: (
            "Operator Execution Route Map", "operator-execution-route-registry.json", "Run-AutoLogonCrashSafe.cmd HOST",
            "Invoke-SasOperatorExecutionRoute.ps1", "UTF-8 Base64", "Known trap this prevents", "C:\\SASAL",
        ),
        REPORT: (
            "## Working", "## Repaired boundary", "## Missing / not proven", "## Current AutoLogon route",
            "Run-AutoLogonCrashSafe.cmd HOST", "UTF-8 Base64", "operator shell", "C:\\SASAL",
        ),
    }
    for path, markers in required_by_file.items():
        text = read(path)
        for marker in markers:
            require(marker in text, f"{path.relative_to(ROOT)} missing: {marker}")


def test_hooks_and_ci() -> None:
    require("validate-operator-execution-route.py" in read(PRE_COMMIT), "pre-commit missing route validator")
    pre_push = read(PRE_PUSH)
    for marker in (
        "validate_freshness_tip()",
        "validate_pushed_tip()",
        'git worktree add --detach --quiet "$wt" "$commit"',
        'git cat-file -e "$commit:harness/validators/validate-operator-execution-route.py"',
        "python3 harness/validators/validate-operator-execution-route.py",
        "dirty local files cannot mask failures",
    ):
        require(marker in pre_push, f"pre-push pushed-tip route validation missing: {marker}")
    prefix = pre_push.split("validate_pushed_tip()", 1)[0]
    require("python3 harness/validators/validate-operator-execution-route.py" not in prefix, "pre-push must validate exact pushed tip, not mutable worktree")

    ci = read(CI)
    for marker in (
        "Operator Execution Route Harness",
        "python -m pip install jsonschema",
        "repository-freshness-before-launch.yaml",
        "scripts/SasPortableLauncher.ps1",
        "Bootstrap-SysAdminSuiteAutoLogon.ps1",
        "Invoke-SasAutoLogonCrashSafeFieldRun.ps1",
        "Invoke-SasAutoLogonFieldDeployment.ps1",
        "Invoke-SasOperatorExecutionRoute.ps1",
        "OperatorExecutionRouteHarness.Tests.ps1",
        "fetch-depth: 0",
        "python harness/validators/validate-operator-execution-route.py",
        "validate-harness-registries.py",
        "test_operational_harness_completeness_contracts.py",
        "git diff --check",
        "runs-on: windows-latest",
    ):
        require(marker in ci, f"operator execution CI missing: {marker}")


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: operator execution route harness contracts ({len(tests)} groups)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
