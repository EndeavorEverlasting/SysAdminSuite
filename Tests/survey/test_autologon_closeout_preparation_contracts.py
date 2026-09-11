#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PREP = ROOT / "Prepare-SysAdminSuiteAutoLogonCloseout.ps1"
CMD = ROOT / "Prepare-SysAdminSuiteAutoLogonCloseout.cmd"
HANDOFF = ROOT / "scripts" / "New-SasAutoLogonDeploymentHandoff.ps1"
RUNBOOK = ROOT / "docs" / "AUTOLOGON_CLOSEOUT_PREPARATION.md"
COMMANDS = ROOT / "harness" / "api" / "harness-command-registry.json"
OUTCOMES = ROOT / "harness" / "api" / "harness-outcome-registry.json"
ARTIFACTS = ROOT / "harness" / "api" / "harness-artifact-registry.json"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_tracked_launcher_hides_preparation_complexity() -> None:
    text = read(CMD)
    assert "Prepare-SysAdminSuiteAutoLogonCloseout.ps1" in text
    assert "HOST" in text
    assert "Guest / ordinary Internet" in text
    assert "does not contact or mutate the target" in text


def test_preparer_owns_current_controller_without_touching_historical_checkouts() -> None:
    text = read(PREP)
    assert "autologon-closeout-controller" in text
    assert "autologon-closeout-controller-preservation" in text
    assert "fetch','--all','--prune','--tags'" in text
    assert "checkout','--detach',$remoteHead" in text
    assert "Repository authority: current origin/main only" in text
    assert "Historical operator checkouts: PRESERVED / NOT USED AS AUTHORITY" in text
    assert "$ref = 'main'" in text
    assert "$repoUrl = 'https://github.com/EndeavorEverlasting/SysAdminSuite.git'" in text
    assert "$runtimeFullPath = 'C:\\SASAL'" in text
    assert "[string]$RepoUrl" not in text
    assert "[string]$RuntimeRoot" not in text
    for forbidden in ("reset --hard", "clean -fd", "Remove-Item -LiteralPath $controllerRoot -Recurse"):
        assert forbidden not in text, forbidden


def test_preparation_is_machine_serialized_and_invalidates_old_handoff_first() -> None:
    text = read(PREP)
    assert "Global\\SysAdminSuite-AutoLogonCloseoutPreparation" in text
    assert "AUTOLOGON_CLOSEOUT_PREPARATION_ALREADY_RUNNING" in text
    assert "Disable-SasPriorCloseoutHandoff" in text
    assert "Run-Prepared-AutoLogon.cmd.disabled" in text
    assert "autologon-closeout-readiness.previous.json" in text
    assert "parent preparation token" in text
    disable_call = text.index("Disable-SasPriorCloseoutHandoff", text.index("if (-not $ControllerMode)"))
    controller_init = text.index("Initialize-SasCurrentController", disable_call)
    assert disable_call < controller_init


def test_git_output_is_empty_safe_under_windows_powershell() -> None:
    text = read(PREP)
    assert "$outputLines = @($output | ForEach-Object { [string]$_ })" in text
    assert "$outputLines.Count -gt 0" in text
    assert "($outputLines -join [Environment]::NewLine).Trim()" in text
    assert "(@($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()" not in text


def test_preparer_reconverges_if_main_moves_during_staging() -> None:
    text = read(PREP)
    assert "MaxFreshnessPasses" in text
    assert "FRESHNESS PASS" in text
    assert "re-check origin/main after runtime staging" in text
    assert "origin/main advanced during preparation" in text
    assert "Re-running canonical Guest refresh so the protected handoff is not born stale." in text
    assert "AUTOLOGON_CLOSEOUT_FRESHNESS_UNSTABLE" in text


def test_preparer_delegates_to_canonical_refresh_and_full_seal_audit() -> None:
    text = read(PREP)
    refresh = "scripts\\Refresh-SasOperatorCommand.ps1"
    audit = "scripts\\Test-SasAutoLogonRuntimeSeal.ps1"
    handoff = "scripts\\New-SasAutoLogonDeploymentHandoff.ps1"
    assert refresh in text
    assert audit in text
    assert handoff in text
    assert text.index(refresh) < text.index(audit) < text.index(handoff)
    assert "sas-autologon-short-runtime/v2" in text
    assert "GUEST_INTERNET" in text
    assert "LOCAL_FILESYSTEM_ONLY" in text
    assert "runtime_remotes_removed" in text
    assert "exact sealed runtime" in text
    assert "AUTOLOGON_CLOSEOUT_PREPARATION_COMPLETED" in text


def test_preparation_never_calls_deployment_engine_directly() -> None:
    text = read(PREP)
    for forbidden in (
        "Invoke-SasAutoLogonFieldDeployment.ps1",
        "Invoke-SasAutoLogonKerberosS4UPilot.ps1",
        "Invoke-SasAutoLogonS4URestartDeployment.ps1",
        "schtasks.exe",
        "Restart-Computer",
    ):
        assert forbidden not in text, forbidden


def test_handoff_is_pinned_atomic_and_uses_only_canonical_protected_bootstrap() -> None:
    text = read(HANDOFF)
    assert "AUTOLOGON_RUNTIME_SEAL_VERIFIED" in text
    assert "READY_FOR_PROTECTED_DEPLOYMENT" in text
    assert "Bootstrap-SysAdminSuiteAutoLogon.cmd" in text
    assert "SAS_EXPECTED" in text
    assert "next_required_network = 'PROTECTED_NORTHWELL'" in text
    assert "target_contact_performed = $false" in text
    assert "target_mutation_performed = $false" in text
    assert "authoritative_for_deployment = $false" in text
    assert "AUTOLOGON_CLOSEOUT_EXISTING_HANDOFF" in text
    assert ".cmd.pending" in text
    assert ".json.pending" in text
    assert "Publish the non-executable receipt first" in text
    assert text.index("Move-Item -LiteralPath $pendingReceipt") < text.index("Move-Item -LiteralPath $pendingHandoff")


def test_no_live_target_or_secret_literal() -> None:
    text = "\n".join(read(path).lower() for path in (PREP, CMD, HANDOFF))
    for forbidden in ("wpj075", "nslijhs.net", "defaultpassword", "password="):
        assert forbidden not in text, forbidden


def test_harness_binds_prepare_artifact_and_protected_deploy_continuation() -> None:
    runbook = read(RUNBOOK)
    commands = read(COMMANDS)
    outcomes = read(OUTCOMES)
    artifacts = read(ARTIFACTS)
    assert "Prepare-SysAdminSuiteAutoLogonCloseout.cmd HOST" in runbook
    assert "Run-Prepared-AutoLogon.cmd" in runbook
    assert '"id":"autologon-closeout-prepare"' in commands
    assert '"id":"autologon-closeout-deploy"' in commands
    assert "%LOCALAPPDATA%\\\\SysAdminSuite\\\\autologon-closeout\\\\Run-Prepared-AutoLogon.cmd" in commands
    assert '"command_id":"autologon-closeout-prepare"' in outcomes
    assert '"command_id":"autologon-closeout-deploy"' in outcomes
    assert '"success_artifact_id":"autologon-closeout-readiness"' in outcomes
    assert '"command_id":"autologon-closeout-deploy","same_turn":true' in outcomes
    assert '"id":"autologon-closeout-readiness"' in artifacts
    assert '"id":"autologon-closeout-deployment-handoff"' in artifacts


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: AutoLogon closeout preparation contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
