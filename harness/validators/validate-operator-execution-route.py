#!/usr/bin/env python3
"""Validate the operator AutoLogon execution route and its durable-evidence chain."""
from __future__ import annotations

import copy
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
COMMANDS = ROOT / "harness/api/harness-command-registry.json"
TERMINAL = ROOT / "harness/api/terminal-evidence-survival-registry.json"
WORKFLOW = ROOT / "harness/workflows/operator-execution-route.yaml"
SKILL = ROOT / "harness/skills/operator-execution-route/SKILL.md"
MAP = ROOT / "harness/maps/OPERATOR_EXECUTION_ROUTE_MAP.md"
REPORT = ROOT / "harness/reports/OPERATOR_EXECUTION_ROUTE_STATUS.md"
FRESH_AGENT = ROOT / "harness/workflows/fresh-agent-intake.yaml"
HELPER = ROOT / "harness/scripts/Invoke-SasOperatorExecutionRoute.ps1"
CRASH_SAFE_CMD = ROOT / "Run-AutoLogonCrashSafe.cmd"
SEALED_CMD = ROOT / "Bootstrap-SysAdminSuiteAutoLogon.cmd"
SEALED_PS1 = ROOT / "Bootstrap-SysAdminSuiteAutoLogon.ps1"
PREPARE = ROOT / "scripts/Prepare-SasAutoLogonShortRuntime.ps1"
CRASH_SAFE_RUNNER = ROOT / "scripts/Invoke-SasAutoLogonCrashSafeFieldRun.ps1"
PORTABLE = ROOT / "scripts/SasPortableLauncher.ps1"
UNIVERSAL = ROOT / "scripts/Invoke-SasUniversalField.ps1"
UNIVERSAL_INSTALLER = ROOT / "scripts/Install-SasUniversalFieldLauncher.ps1"
WINDOWS_ROUTE_TEST = ROOT / "Tests/PowerShell/OperatorExecutionRouteHarness.Tests.ps1"
WINDOWS_HASH_TEST = ROOT / "Tests/PowerShell/AutoLogonProtectedHashing.Tests.ps1"
UNIVERSAL_CONTRACT = ROOT / "Tests/survey/test_universal_field_platform_contracts.py"
PROTECTED_CONTRACT = ROOT / "Tests/survey/test_autologon_protected_bootstrap_contracts.py"
CRASH_SAFE_CONTRACT = ROOT / "Tests/survey/test_autologon_crash_safe_field_runner_contracts.py"
SHORT_RUNTIME_CONTRACT = ROOT / "Tests/survey/test_autologon_short_runtime_staging_contracts.py"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"
ROUTE_CI = ROOT / ".github/workflows/operator-execution-route-harness.yml"
UNIVERSAL_CI = ROOT / ".github/workflows/universal-field-platform.yml"
CRASH_SAFE_CI = ROOT / ".github/workflows/autologon-crash-safe-field-runner.yml"

COMPONENTS = (
    REGISTRY, SCHEMA, MANIFEST, MANIFEST_SCHEMA, VALIDATORS, COMMANDS, TERMINAL,
    WORKFLOW, SKILL, MAP, REPORT, FRESH_AGENT, HELPER, CRASH_SAFE_CMD, SEALED_CMD,
    SEALED_PS1, PREPARE, CRASH_SAFE_RUNNER, PORTABLE, UNIVERSAL, UNIVERSAL_INSTALLER,
    WINDOWS_ROUTE_TEST, WINDOWS_HASH_TEST, UNIVERSAL_CONTRACT, PROTECTED_CONTRACT,
    CRASH_SAFE_CONTRACT, SHORT_RUNTIME_CONTRACT, PRE_COMMIT, PRE_PUSH, ROUTE_CI,
    UNIVERSAL_CI, CRASH_SAFE_CI,
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


def exact_keys(value: object, expected: set[str], label: str) -> None:
    require(isinstance(value, dict), f"{label} must be an object")
    actual = set(value)
    require(actual == expected, f"{label} key drift; missing={sorted(expected-actual)} unknown={sorted(actual-expected)}")


def one(items: object, key: str, value: str) -> dict:
    require(isinstance(items, list), f"{key} collection must be an array")
    matches = [item for item in items if isinstance(item, dict) and str(item.get(key, "")) == value]
    require(len(matches) == 1, f"expected one {key}={value}, found {len(matches)}")
    return matches[0]


def tracked(path: Path) -> bool:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", path.relative_to(ROOT).as_posix()],
        text=True, capture_output=True, check=False,
    )
    return result.returncode == 0


def tracked_relative(relative: str, label: str) -> Path:
    rel = Path(relative)
    require(not rel.is_absolute(), f"{label} must be repository-relative: {relative}")
    candidate = (ROOT / rel).resolve()
    try:
        candidate.relative_to(ROOT.resolve())
    except ValueError as exc:
        raise AssertionError(f"{label} escapes repository root: {relative}") from exc
    require(candidate.is_file(), f"{label} missing: {relative}")
    require(tracked(candidate), f"{label} untracked: {relative}")
    return candidate


def validate_registry_without_jsonschema(data: object, schema: object) -> None:
    require(isinstance(data, dict), "route registry must be an object")
    require(isinstance(schema, dict), "route schema must be an object")
    exact_keys(data, {"schema_version", "repository", "policy", "routes"}, "route registry")
    require(data["schema_version"] == "sas-operator-execution-route-registry/v1", "route registry schema version drift")
    require(data["repository"] == "EndeavorEverlasting/SysAdminSuite", "route registry repository drift")
    require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", "route schema must be Draft 2020-12")
    require(schema.get("properties", {}).get("schema_version", {}).get("const") == data["schema_version"], "schema/registry version mismatch")

    policy = data["policy"]
    exact_keys(policy, POLICY_KEYS, "route policy")
    for key in POLICY_KEYS:
        require(type(policy[key]) is bool and policy[key] is True, f"route policy {key} must remain boolean true")

    routes = data["routes"]
    require(isinstance(routes, list) and routes, "routes must be non-empty")
    for index, route in enumerate(routes):
        exact_keys(route, ROUTE_KEYS, f"route[{index}]")
        for key in ROUTE_KEYS - {"path_resolution"}:
            require(isinstance(route[key], str) and bool(route[key]), f"route[{index}].{key} must be a non-empty string")
        require(route["platform"] == "windows-powershell", "route platform drift")
        require(route["target_placeholder"] == "HOST_B64", "target placeholder drift")
        require(route["target_encoding"] == "utf8-base64", "target encoding drift")
        path = route["path_resolution"]
        exact_keys(path, PATH_KEYS, f"route[{index}].path_resolution")
        require(isinstance(path["strategy_order"], list) and path["strategy_order"], "strategy_order must be non-empty")
        require(all(isinstance(v, str) and v for v in path["strategy_order"]), "strategy_order entries must be strings")
        require(isinstance(path["required_files"], list) and path["required_files"], "required_files must be non-empty")
        require(all(isinstance(v, str) and v for v in path["required_files"]), "required_files entries must be strings")
        require(len(path["required_files"]) == len(set(path["required_files"])), "required_files must be unique")
        require(type(path["fail_closed"]) is bool and path["fail_closed"] is True, "path resolution must fail closed")


def expect_schema_failure(data: dict, label: str) -> None:
    try:
        validate_registry_without_jsonschema(data, load(SCHEMA))
    except AssertionError:
        return
    raise AssertionError(f"dependency-free schema validation accepted invalid fixture: {label}")


def test_components_exist_and_are_tracked() -> None:
    for path in COMPONENTS:
        require(path.is_file(), f"missing component: {path.relative_to(ROOT)}")
        require(tracked(path), f"component is not tracked: {path.relative_to(ROOT)}")


def test_registry_schema_is_blocking_without_optional_dependency() -> None:
    data = load(REGISTRY)
    schema = load(SCHEMA)
    validate_registry_without_jsonschema(data, schema)
    for label, mutate in (
        ("additionalProperties", lambda d: d["routes"][0].__setitem__("unexpected", True)),
        ("required", lambda d: d["routes"][0].pop("success_artifact")),
        ("constant", lambda d: d["routes"][0].__setitem__("target_encoding", "plain")),
        ("uniqueItems", lambda d: d["routes"][0]["path_resolution"]["required_files"].append(d["routes"][0]["path_resolution"]["required_files"][0])),
    ):
        invalid = copy.deepcopy(data)
        mutate(invalid)
        expect_schema_failure(invalid, label)
    if jsonschema is not None:
        jsonschema.Draft202012Validator.check_schema(schema)
        jsonschema.Draft202012Validator(schema).validate(data)


def test_autologon_route_uses_sealed_bootstrap_not_installed_dispatcher() -> None:
    route = one(load(REGISTRY)["routes"], "command_id", "autologon-remote")
    require(route["id"] == "autologon-remote-crash-safe", "route id drift")
    require(route["required_network"] == "PROTECTED_NORTHWELL", "network authority drift")
    require(route["inner_product_command"] == "sas autologon Remote HOST", "canonical command drift")
    require(route["operator_helper"] == "harness/scripts/Invoke-SasOperatorExecutionRoute.ps1", "fallback helper drift")
    require(route["target_encoding"] == "utf8-base64", "target transport drift")
    pattern = re.compile(route["target_validation_pattern"])
    require(pattern.fullmatch("server01.example.net") is not None, "valid FQDN rejected")
    require(pattern.fullmatch("server01'; Write-Output INJECTED; '") is None, "hostile target accepted")
    tracked_relative(route["repository_freshness_dependency"], "freshness dependency")

    path = route["path_resolution"]
    require(path["strategy_order"] == ["installed-sas-sealed-bootstrap", "cached-repo-root"], "execution strategy drift")
    require(path["installed_sas_probe"] == "sas repo", "installed SAS locator drift")
    require(path["cache_path"] == r"%LOCALAPPDATA%\SysAdminSuite\repo-root.txt", "cache path drift")
    expected = {
        "Run-AutoLogonCrashSafe.cmd",
        "scripts/Invoke-SasAutoLogonCrashSafeFieldRun.ps1",
        "scripts/Invoke-SasAutoLogonFieldDeployment.ps1",
        "harness/scripts/Invoke-SasOperatorExecutionRoute.ps1",
    }
    require(set(path["required_files"]) == expected, "fallback dependency drift")
    for relative in path["required_files"]:
        tracked_relative(relative, "fallback dependency")

    template = route["operator_command_template"]
    require(template.count("HOST_B64") == 1, "encoded target placeholder must appear exactly once")
    for marker in (
        "$targetBase64='HOST_B64'", "FromBase64String($targetBase64)",
        "SAS_OPERATOR_ROUTE_TARGET_ENCODING_INVALID", "SAS_OPERATOR_ROUTE_TARGET_INVALID",
        "$sasCommand=Get-Command sas", "$sealedRoot=(& sas repo", "Bootstrap-SysAdminSuiteAutoLogon.cmd",
        "& $sealedBootstrap $target", "repo-root.txt", "operator-execution-route-registry.json",
        "$route.path_resolution.required_files", "$route.operator_helper",
        "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $helper $targetBase64",
        "$code=[int]$LASTEXITCODE", "$global:LASTEXITCODE=$code", "Operator route failed with exit code",
    ):
        require(marker in template, f"route template missing: {marker}")
    require("& sas autologon Remote $target" not in template, "route must bypass possibly stale installed AutoLogon dispatcher")
    require("powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command" not in template, "nested -Command payload forbidden")
    require("exit $LASTEXITCODE" not in template, "route must preserve parent shell")


def test_v2_sealed_runtime_is_git_free_and_get_file_hash_free() -> None:
    prepare = read(PREPARE)
    bootstrap = read(SEALED_PS1)
    runner = read(CRASH_SAFE_RUNNER)
    portable = read(PORTABLE)

    for text, label in ((prepare, "prepare"), (bootstrap, "bootstrap")):
        require("function Get-SasSha256Hex" in text, f"{label} missing .NET SHA-256 helper")
        require("[Security.Cryptography.SHA256]::Create()" in text, f"{label} missing .NET SHA-256 implementation")
        require("Get-FileHash" not in text, f"{label} reintroduced Get-FileHash dependency")
    require("sas-autologon-short-runtime/v2" in prepare, "Guest preparer must emit v2 seal")
    require("tracked_file_hash_algorithm = 'SHA256'" in prepare, "Guest preparer missing SHA256 seal metadata")
    require("tracked_file_hashes = $trackedFileHashes" in prepare, "Guest preparer missing tracked-file hashes")
    require("sas-autologon-short-runtime/v2" in bootstrap, "protected bootstrap must require v2 seal")
    require("$actualHash = Get-SasSha256Hex -LiteralPath $fullPath" in bootstrap, "protected bootstrap does not verify sealed hash")
    require("AUTOLOGON_RUNTIME_SEAL_MISMATCH" in bootstrap, "protected bootstrap missing seal mismatch disposition")
    for forbidden in ("Resolve-SasGitExecutable", "Invoke-SasLocalGit", "Get-SasLocalGitScalar", "git.exe", "rev-parse"):
        require(forbidden not in bootstrap, f"protected bootstrap reintroduced Git dependency: {forbidden}")
    require("-RepositoryRoot $RuntimeRoot -RepositoryHead $preparedCommit -ConfirmDeployment" in bootstrap, "sealed commit not passed into crash-safe runner")
    require("[string]$RepositoryHead" in runner, "crash-safe runner missing sealed repository identity input")
    require("git -C" not in runner and "rev-parse HEAD" not in runner, "crash-safe runner reintroduced protected Git")
    require("sas-autologon-short-runtime/v2" in portable, "portable launcher must understand v2 runtime")
    require("complete SHA-256 tracked-file seal" in portable, "portable launcher must reject incomplete v2 seals")


def test_installed_universal_remote_converges_to_same_crash_safe_bootstrap() -> None:
    installer = read(UNIVERSAL_INSTALLER)
    require('powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-SasUniversalField.ps1" %*' in installer,
            "installed sas.cmd no longer enters universal field launcher")
    launcher = read(UNIVERSAL)
    block = launcher.split("    'autologon' {", 1)[1].split("\n    'cybernet' {", 1)[0]
    require("Resolve-SasInstalledAutoLogonBootstrap" in launcher, "universal launcher missing AutoLogon bootstrap resolver")
    require("Join-Path $runtimeRoot 'Bootstrap-SysAdminSuiteAutoLogon.cmd'" in launcher, "universal launcher does not resolve sealed bootstrap")
    require("if ($mode -eq 'remote')" in block and "& $bootstrap $target" in block, "universal Remote does not invoke sealed bootstrap")
    require("& $recoveryLauncher Recover $target" in block, "universal Recover must remain recovery-only")
    require("& $recoveryLauncher Remote $target" not in block, "universal Remote must not bypass crash-safe bootstrap")


def test_crash_safe_evidence_chain_and_field_regression() -> None:
    cmd = read(SEALED_CMD)
    bootstrap = read(SEALED_PS1)
    runner = read(CRASH_SAFE_RUNNER)
    hash_test = read(WINDOWS_HASH_TEST)
    require("Bootstrap-SysAdminSuiteAutoLogon.ps1" in cmd and "-ConfirmVpnPosture" in cmd, "sealed CMD bootstrap drift")
    require("PRE-STAGED RUNTIME VERIFIED - STARTING CRASH-SAFE AUTOLOGON FIELD TRANSACTION" in bootstrap, "bootstrap does not enter crash-safe transaction")
    require("last-autologon-field-run.json" in bootstrap, "bootstrap no longer reports latest pointer")
    for marker in ("field-runs\\autologon", "field-run-result.json", "Start-Transcript", "last-autologon-field-run.json"):
        require(marker in runner, f"crash-safe runner missing durable evidence marker: {marker}")
    require("FIELD_FIXTURE_GET_FILE_HASH_MUST_NOT_BE_CALLED" in hash_test, "Windows fixture does not model missing/broken Get-FileHash")
    require("Get-SasSha256Hex" in hash_test, "Windows fixture does not execute production helper")
    require("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" in hash_test, "Windows fixture lacks known SHA-256 oracle")


def test_central_registration_and_existing_authorities_align() -> None:
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
        require(bool(item), f"operational manifest missing {component_id}")
        require(item["kind"] == kind and item["path"] == path, f"manifest drift: {component_id}")
        require(item["required"] is True and item["tracked"] is True, f"component must remain required/tracked: {component_id}")
    require("execution_route_registry" in load(MANIFEST_SCHEMA)["properties"]["components"]["items"]["properties"]["kind"]["enum"], "manifest schema missing execution route kind")
    entry = one(load(VALIDATORS)["validators"], "id", "operator-execution-route-contracts")
    require(entry["blocking"] is True, "route validator must remain blocking")
    require(entry["command"] == "python harness/validators/validate-operator-execution-route.py", "validator command drift")
    command = one(load(COMMANDS)["commands"], "id", "autologon-remote")
    require(command["command"] == "sas autologon Remote HOST" and command["mutation"] == "authorized_target_mutation", "command authority drift")
    front = one(load(TERMINAL)["front_doors"], "command_id", "autologon-remote")
    require(front["latest_pointer"] == r"%LOCALAPPDATA%/SysAdminSuite/last-autologon-field-run.json", "terminal evidence pointer drift")


def test_workflow_skill_map_report_and_hooks_track_final_topology() -> None:
    for path, markers in {
        WORKFLOW: ("sealed C:\\SASAL runtime", "Bootstrap-SysAdminSuiteAutoLogon.cmd", "sas repo", "never interpolate the raw explicit_target"),
        SKILL: ("C:\\SASAL", "Bootstrap-SysAdminSuiteAutoLogon.cmd", "Invoke-SasUniversalField.ps1", "one copy-paste"),
        MAP: ("C:\\SASAL", "Bootstrap-SysAdminSuiteAutoLogon.cmd", "Invoke-SasUniversalField.ps1", "Known trap this prevents"),
        REPORT: ("C:\\SASAL", "Bootstrap-SysAdminSuiteAutoLogon.cmd", "Invoke-SasUniversalField.ps1", "last-autologon-field-run.json"),
        FRESH_AGENT: ("operator-execution-route-registry.json", "operator-execution-route.yaml", "validate-operator-execution-route.py"),
    }.items():
        text = read(path)
        for marker in markers:
            require(marker in text, f"{path.relative_to(ROOT)} missing marker: {marker}")

    require("validate-operator-execution-route.py" in read(PRE_COMMIT), "pre-commit missing route validator")
    pre_push = read(PRE_PUSH)
    for marker in ("validate_pushed_tip()", 'git worktree add --detach --quiet "$wt" "$commit"', "validate-operator-execution-route.py", "dirty local files cannot mask failures"):
        require(marker in pre_push, f"pre-push exact-tip proof missing: {marker}")


def test_ci_reexecutes_when_runtime_or_routing_surfaces_change() -> None:
    route_ci = read(ROUTE_CI)
    for marker in (
        "Operator Execution Route Harness", "Bootstrap-SysAdminSuiteAutoLogon.cmd",
        "Bootstrap-SysAdminSuiteAutoLogon.ps1", "scripts/Invoke-SasUniversalField.ps1",
        "scripts/SasPortableLauncher.ps1", "OperatorExecutionRouteHarness.Tests.ps1",
        "python harness/validators/validate-operator-execution-route.py", "runs-on: windows-latest",
    ):
        require(marker in route_ci, f"route CI missing dependency: {marker}")
    universal_ci = read(UNIVERSAL_CI)
    for marker in ("scripts/Invoke-SasUniversalField.ps1", "Bootstrap-SysAdminSuiteAutoLogon.cmd", "Bootstrap-SysAdminSuiteAutoLogon.ps1"):
        require(marker in universal_ci, f"universal CI missing AutoLogon dependency: {marker}")
    crash_ci = read(CRASH_SAFE_CI)
    for marker in (
        "Bootstrap-SysAdminSuiteAutoLogon.ps1", "scripts/Prepare-SasAutoLogonShortRuntime.ps1",
        "scripts/Invoke-SasAutoLogonCrashSafeFieldRun.ps1", "AutoLogonProtectedHashing.Tests.ps1",
        "Execute protected SHA-256 compatibility fixture",
    ):
        require(marker in crash_ci, f"crash-safe CI missing field regression: {marker}")


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: operator execution route harness contracts ({len(tests)} groups)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
