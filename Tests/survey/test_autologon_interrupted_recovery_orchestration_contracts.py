#!/usr/bin/env python3
"""Contracts for local-evidence-driven interrupted S4U recovery before AutoLogon apply."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DISCOVERY = ROOT / "scripts" / "Recover-SasLatestInterruptedAutoLogonS4U.ps1"
EXACT = ROOT / "scripts" / "Complete-SasInterruptedAutoLogonS4URecovery.ps1"
ONSITE = ROOT / "scripts" / "Invoke-SasAutoLogonOnsite.ps1"
CMD = ROOT / "Run-AutoLogonOnsite.cmd"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_discovery_uses_only_local_durable_probe_lifecycle_identity() -> None:
    text = read(DISCOVERY)
    for marker in (
        "Get-SasEvidenceRoots -RepoRoot $repoRoot",
        "s4u_probe_lifecycle.json",
        "run_id",
        "task_name",
        "local_s4u_root",
        "install_or_after_evidence_present",
        "NO_INTERRUPTED_PROBE_RUN_FOUND",
        "INTERRUPTED_PROBE_RUNS_RECOVERED",
    ):
        assert marker in text, marker
    for forbidden in (
        "schtasks.exe",
        "'/Query'",
        '"/Query"',
        "Get-ScheduledTask",
        "MSFT_ScheduledTask",
        "Win32_ScheduledJob",
    ):
        assert forbidden not in text, forbidden


def test_discovery_fails_closed_if_install_or_after_evidence_exists() -> None:
    text = read(DISCOVERY)
    for marker in (
        "s4u-install-worker.ps1",
        "s4u_install_lifecycle.json",
        "s4u_install_result.json",
        "after_lifecycle.json",
        "after_snapshot.json",
        "Refusing automatic recovery or redeployment",
    ):
        assert marker in text, marker
    exact_call = text.index("& $recoveryScript")
    unsafe_gate = text.index("if ($unsafe.Count -gt 0)")
    assert unsafe_gate < exact_call


def test_discovery_invokes_exact_recovery_with_recorded_identity_only() -> None:
    text = read(DISCOVERY)
    call = (
        "& $recoveryScript -ComputerName ([string]$item.target) -RunId ([string]$item.run_id) "
        "-TaskName ([string]$item.task_name) -LocalS4URoot ([string]$item.local_s4u_root) "
        "-ConfirmRecovery -TimeoutSeconds $TimeoutSeconds"
    )
    assert call in text
    assert "autologon_installer_launched=$false" in text
    assert "exact_cleanup_only=$true" in text


def test_exact_recovery_can_remove_only_the_recorded_task_then_exact_run_root() -> None:
    text = read(EXACT)
    query = text.index("@('/Query','/S',$ComputerName,'/TN',$TaskName)")
    delete = text.index("@('/Delete','/S',$ComputerName,'/TN',$TaskName,'/F')", query)
    verify = text.index("@('/Query','/S',$ComputerName,'/TN',$TaskName)", delete)
    cleanup = text.index("& $cleanupScript -ComputerName $ComputerName -RunId $RunId", verify)
    assert query < delete < verify < cleanup
    for marker in (
        "task_initially_present",
        "task_delete_attempted",
        "task_delete_succeeded",
        "task_absent_before_cleanup",
        "task_absent_after_cleanup",
        "exact_run_root_absent",
    ):
        assert marker in text, marker


def test_exact_recovery_retrieves_probe_result_before_any_destructive_cleanup() -> None:
    text = read(EXACT)
    presence = text.index("Test-SasBoundedPath -Path $remoteProbeResult")
    copy = text.index("Copy-SasBoundedFile -Source $remoteProbeResult", presence)
    task_delete = text.index("@('/Delete','/S',$ComputerName,'/TN',$TaskName,'/F')", copy)
    run_cleanup = text.index("& $cleanupScript -ComputerName $ComputerName -RunId $RunId", task_delete)
    assert presence < copy < task_delete < run_cleanup
    assert "No cleanup was attempted" in text


def test_normal_remote_deployment_runs_interrupted_recovery_gate_before_apply() -> None:
    text = read(ONSITE)
    assert "'Remote','S4U'" in text
    recovery = text.index("& $s4uRecoveryScript -ComputerName $target -ConfirmRecovery -PassThru")
    apply = text.index("& $s4uDeploymentScript -ComputerName $target -AllowTargetMutation -ConfirmDeployment", recovery)
    assert recovery < apply
    assert "Interrupted-run gate did not return a completed classification. AutoLogon was not started." in text
    assert "[ValidateSet('Menu','Prepare','Validate','Pilot','Remote','S4U','Recover','Evidence')]" in text
    assert "'Recover' {" in text


def test_cmd_surface_can_route_recover_target_without_manual_fragments() -> None:
    text = read(CMD)
    assert 'Invoke-SasAutoLogonOnsite.ps1" -Action "%~1" -ComputerName "%~2"' in text
    assert "try" not in text.lower()
    assert "finally" not in text.lower()


def test_no_live_target_user_or_secret_literals() -> None:
    combined = "\n".join(read(path) for path in (DISCOVERY, EXACT, ONSITE, CMD)).lower()
    for forbidden in (
        "wpj075opr046",
        "pa_rperez26",
        "defaultpassword_value",
        "get-credential",
        "securestring",
    ):
        assert forbidden not in combined, forbidden


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: interrupted AutoLogon S4U recovery orchestration contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
