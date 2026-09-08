#!/usr/bin/env python3
"""Validate that registered field front doors preserve evidence beyond terminal lifetime."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "harness/api/terminal-evidence-survival-registry.json"
SCHEMA = ROOT / "schemas/harness/terminal-evidence-survival-registry.schema.json"
COMMANDS = ROOT / "harness/api/harness-command-registry.json"
ARTIFACTS = ROOT / "harness/api/harness-artifact-registry.json"
OUTCOMES = ROOT / "harness/api/harness-outcome-registry.json"
LAUNCHER = ROOT / "Run-AutoLogonCrashSafe.cmd"
RUNNER = ROOT / "scripts/Invoke-SasAutoLogonCrashSafeFieldRun.ps1"
PRODUCT_CONTRACT = ROOT / "Tests/survey/test_autologon_crash_safe_field_runner_contracts.py"
WORKFLOW = ROOT / "harness/workflows/terminal-evidence-survival.yaml"
SKILL = ROOT / "harness/skills/terminal-evidence-survival/SKILL.md"
FRESH_AGENT = ROOT / "harness/workflows/fresh-agent-intake.yaml"
DEPLOYMENT_WORKFLOW = ROOT / "harness/workflows/cybernet-autologon-deployment-state.yaml"
DEPLOYMENT_SKILL = ROOT / "harness/skills/cybernet-autologon-deployment-state/SKILL.md"
REPORT = ROOT / "docs/TERMINAL_EVIDENCE_SURVIVAL.md"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"
OFFLINE = ROOT / "tests/survey/run_offline_survey_tests.sh"
CI = ROOT / ".github/workflows/terminal-evidence-survival.yml"


def read(path: Path) -> str:
    assert path.is_file(), f"missing terminal-evidence component: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def tracked(path: Path) -> bool:
    relative = path.relative_to(ROOT).as_posix()
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", relative],
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def one(items: list[dict], key: str, value: str) -> dict:
    matches = [item for item in items if str(item.get(key, "")) == value]
    assert len(matches) == 1, f"expected one {key}={value}, found {len(matches)}"
    return matches[0]


def main() -> int:
    registry = load(REGISTRY)
    schema = load(SCHEMA)
    commands = load(COMMANDS)["commands"]
    artifacts = load(ARTIFACTS)["artifacts"]
    outcomes = load(OUTCOMES)["contracts"]

    assert registry["schema_version"] == "sas-terminal-evidence-survival-registry/v1"
    assert registry["repository"] == "EndeavorEverlasting/SysAdminSuite"
    assert schema["$schema"].endswith("draft/2020-12/schema")
    assert schema["properties"]["schema_version"]["const"] == registry["schema_version"]
    for key, value in registry["policy"].items():
        assert value is True, f"terminal evidence policy disabled: {key}"

    front = one(registry["front_doors"], "id", "autologon-crash-safe-field-run")
    assert front["command_id"] == "autologon-remote"
    assert front["operator_command"] == "Run-AutoLogonCrashSafe.cmd HOST"
    assert front["operator_entrypoint"] == "Run-AutoLogonCrashSafe.cmd"
    assert front["runner"] == "scripts/Invoke-SasAutoLogonCrashSafeFieldRun.ps1"
    assert front["inner_entrypoint"] == "scripts/Invoke-SasAutoLogonOnsite.ps1"
    assert front["inner_action"] == "Remote"
    assert front["offline_recovery_entrypoint"] == "scripts/Show-SasOperatorEvidence.ps1"

    command = one(commands, "id", "autologon-remote")
    assert command["command"] == "sas autologon Remote HOST"
    assert command["source_of_truth"] == "scripts/Invoke-SasAutoLogonFieldDeployment.ps1"
    assert command["mutation"] == "authorized_target_mutation"
    assert command["network"] is True

    artifact_by_id = {item["id"]: item for item in artifacts}
    assert front["success_artifact_id"] == "autologon-field-deployment-result"
    for artifact_id in front["survival_artifact_ids"]:
        assert artifact_id in artifact_by_id, f"unregistered survival artifact: {artifact_id}"
        artifact = artifact_by_id[artifact_id]
        assert artifact["tracked"] is False, f"runtime evidence must remain untracked: {artifact_id}"
        assert artifact["contains_live_data"] is True, f"runtime evidence must be live-data classified: {artifact_id}"
    outcome = one(outcomes, "command_id", "autologon-remote")
    assert outcome["success_outcome"] == "product_deployed"
    assert outcome["success_artifact_id"] == front["success_artifact_id"]

    launcher = read(LAUNCHER)
    normalized_launcher = launcher.replace("%%", "%")
    for marker in front["required_launcher_markers"]:
        assert marker.lower() in normalized_launcher.lower(), f"launcher lost crash-safe marker: {marker}"
    assert "set \"SAS_EXIT=%ERRORLEVEL%\"" in launcher
    assert "endlocal & exit /b" in launcher

    runner = read(RUNNER)
    for marker in front["required_runner_markers"]:
        assert marker in runner, f"runner lost evidence-survival marker: {marker}"
    assert "target_contact_performed_by_runner = $false" in runner
    assert "target_mutation_performed_by_runner = $false" in runner
    assert "Invoke-SasAutoLogonOnsite.ps1" in runner
    assert "'-Action', 'Remote'" in runner
    initial_result = runner.index("$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath")
    child_launch = runner.index("& powershell.exe @childArguments")
    recovery_launch = runner.index("& powershell.exe @evidenceArguments")
    # The crash-safe runner may use nested try/finally blocks around child execution details
    # (for example, restoring ErrorActionPreference). Locate the outer persistence finally only
    # after offline evidence recovery has been launched.
    finally_block = runner.index("finally {", recovery_launch)
    final_result = runner.index("$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath", initial_result + 1)
    latest_pointer = runner.index("Set-Content -LiteralPath $latestPointerPath")
    failure_throw = runner.index("Diagnostics were preserved under:")
    assert initial_result < child_launch < recovery_launch < finally_block < final_result < latest_pointer < failure_throw

    product_contract = read(PRODUCT_CONTRACT)
    for marker in (
        "test_stable_diagnostics_survive_terminal_loss",
        "test_offline_evidence_recovery_runs_after_child",
        "test_cmd_keeps_visible_failure_boundary",
        "evidence_recovery_exit_code",
    ):
        assert marker in product_contract, f"merged crash-safe product contract drifted: {marker}"

    workflow = read(WORKFLOW)
    skill = read(SKILL)
    fresh_agent = read(FRESH_AGENT)
    deployment_workflow = read(DEPLOYMENT_WORKFLOW)
    deployment_skill = read(DEPLOYMENT_SKILL)
    report = read(REPORT)
    for marker in (
        "workflow_id: terminal-evidence-survival",
        "Run-AutoLogonCrashSafe.cmd HOST",
        "terminal lifetime is not evidence lifetime",
        "offline evidence recovery",
        "propagate every nonzero exit code",
    ):
        assert marker.lower() in workflow.lower(), f"terminal workflow missing: {marker}"
    for marker in (
        "## Trigger",
        "## Required inputs",
        "## Procedure",
        "## Failure handling",
        "## Expected outputs",
        "## Proof ceiling",
        "Run-AutoLogonCrashSafe.cmd HOST",
        "last-autologon-field-run.json",
    ):
        assert marker in skill, f"terminal skill missing: {marker}"
    for marker in (
        "harness/api/terminal-evidence-survival-registry.json",
        "harness/skills/terminal-evidence-survival/SKILL.md",
        "Run-AutoLogonCrashSafe.cmd HOST",
        "recover the stable latest pointer",
    ):
        assert marker in fresh_agent, f"fresh-agent terminal routing missing: {marker}"
    for marker in (
        "harness/api/terminal-evidence-survival-registry.json",
        "Run-AutoLogonCrashSafe.cmd HOST",
        "crash-safe field-run result",
        "inspect the stable latest pointer",
    ):
        assert marker in deployment_workflow, f"deployment workflow terminal routing missing: {marker}"
    for marker in (
        "harness/api/terminal-evidence-survival-registry.json",
        "Run-AutoLogonCrashSafe.cmd HOST",
        "last-autologon-field-run.json",
        "rerunning merely because the terminal closed",
    ):
        assert marker in deployment_skill, f"deployment skill terminal routing missing: {marker}"
    for marker in (
        "What survives",
        "What remains unproven",
        "Run-AutoLogonCrashSafe.cmd HOST",
        "last-autologon-field-run.json",
        "validate-terminal-evidence-survival.py",
    ):
        assert marker in report, f"terminal operator report missing: {marker}"

    validator_marker = "validate-terminal-evidence-survival.py"
    for path in (PRE_COMMIT, PRE_PUSH, OFFLINE, CI):
        assert validator_marker in read(path), f"terminal evidence validator not wired: {path.relative_to(ROOT)}"

    for path in (
        REGISTRY,
        SCHEMA,
        WORKFLOW,
        SKILL,
        FRESH_AGENT,
        DEPLOYMENT_WORKFLOW,
        DEPLOYMENT_SKILL,
        REPORT,
        CI,
        LAUNCHER,
        RUNNER,
        PRODUCT_CONTRACT,
    ):
        assert tracked(path), f"terminal evidence component is not tracked: {path.relative_to(ROOT)}"

    print("PASS: terminal evidence survival harness contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
