#!/usr/bin/env python3
"""Static contracts for the field-proven AutoLogon S4U hang hardening."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PILOT = ROOT / "scripts" / "Invoke-SasAutoLogonKerberosS4UPilot.ps1"
RESTART = ROOT / "scripts" / "Invoke-SasAutoLogonS4URestartDeployment.ps1"
BOUNDED = ROOT / "scripts" / "SasBoundedNative.psm1"
CLEANUP = ROOT / "scripts" / "Remove-SasExactRemoteAutoLogonRunRoot.ps1"
RECOVERY = ROOT / "scripts" / "Complete-SasInterruptedAutoLogonS4URecovery.ps1"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_every_s4u_task_scheduler_verb_uses_bounded_native() -> None:
    text = read(PILOT)
    assert "function Invoke-SasS4UNative" not in text
    assert "Invoke-SasBoundedNative" in text
    for verb in ("'/Create'", "'/Run'", "'/Delete'", "'/Query'"):
        assert verb in text, verb
    assert "-TimeoutSeconds $NativeTimeoutSeconds" in text
    for classification in (
        "S4U_${modeUpper}_CREATE_TIMEOUT",
        "S4U_${modeUpper}_RUN_TIMEOUT",
        "S4U_${modeUpper}_RESULT_TIMEOUT",
    ):
        assert classification in text, classification


def test_restart_task_scheduler_is_also_bounded() -> None:
    text = read(RESTART)
    assert "function Invoke-SasAutoLogonDeploymentNative" not in text
    assert "Invoke-SasBoundedNative" in text
    assert "Invoke-SasAutoLogonBoundedTask" in text
    for verb in ("'/Create'", "'/Run'", "'/Delete'", "'/Query'"):
        assert verb in text, verb
    assert "NativeTaskTimeoutSeconds" in text


def test_bounded_native_timeout_kills_only_the_isolated_child_tree() -> None:
    text = read(BOUNDED)
    for marker in (
        "process.WaitForExit($TimeoutSeconds * 1000)",
        "taskkill.exe",
        '"/PID $ProcessId /T /F"',
        "child_tree_termination_attempted",
        "child_tree_terminated",
        "timed_out = $true",
        "timeout_seconds = $TimeoutSeconds",
    ):
        assert marker in text, marker


def test_remote_result_existence_and_copy_are_bounded() -> None:
    text = read(PILOT)
    assert "function Test-SasS4UBoundedRemotePath" in text
    assert "function Copy-SasS4UBoundedRemoteResult" in text
    assert "Invoke-SasS4UBoundedPowerShell" in text
    assert "while (-not (Test-Path -LiteralPath $RemoteResultUnc" not in text
    assert "Test-SasS4UBoundedRemotePath -Path $RemoteResultUnc -PathType Leaf" in text
    assert "Copy-SasS4UBoundedRemoteResult -Source $RemoteResultUnc" in text
    assert "[Math]::Min($RemoteProbeTimeoutSeconds, $remainingSeconds)" in text


def test_exact_task_identity_is_persisted_before_create() -> None:
    text = read(PILOT)
    checkpoint = text.index("# Required crash-recovery checkpoint: exact task/run identity exists before schtasks /Create.")
    save = text.index("Save-SasS4UTaskLifecycle -Path $LifecyclePath -Lifecycle $lifecycle", checkpoint)
    create = text.index("'/Create'", save)
    assert checkpoint < save < create
    for marker in (
        "run_id = $RunId",
        "mode = $Mode",
        "task_name = $TaskName",
        "target = $Target",
        "s4u_principal = $PrincipalName",
        "remote_worker_path = $WorkerPath",
        "remote_result_path = $RemoteResultPath",
        "local_result_path = $LocalResultPath",
        "create_attempted = $false",
        "create_succeeded = $false",
        "run_attempted = $false",
        "run_succeeded = $false",
        "result_retrieved = $false",
        "delete_attempted = $false",
        "delete_succeeded = $false",
        "absent_verified = $false",
        "current_stage = 'identity_checkpointed_before_create'",
    ):
        assert marker in text, marker


def test_probe_failure_cannot_generate_or_launch_installer_phase_first() -> None:
    text = read(PILOT)
    probe_call = text.index("Invoke-SasS4UTask -Target $resolvedTarget -TaskName $probeTask")
    probe_gate = text.index("if (-not $probeLifecycle.result_retrieved", probe_call)
    install_worker = text.index("$installWorkerLocal =", probe_gate)
    install_call = text.index("Invoke-SasS4UTask -Target $resolvedTarget -TaskName $installTask", install_worker)
    assert probe_call < probe_gate < install_worker < install_call
    assert "S4U_${modeUpper}_CREATE_TIMEOUT" in text


def test_durable_source_and_baseline_policy_are_consumed_directly() -> None:
    text = read(PILOT)
    for marker in (
        "SasSoftwareSourceIdentity.psm1",
        "Resolve-SasCanonicalSoftwareSourceIdentity -ApprovedServer $package.source_server",
        "address_overlap_verified",
        "sourceIdentity.cifs_spn",
        "sourceIdentity.canonical_unc_root",
        "SasAutoLogonBaselinePolicy.psm1",
        "Test-SasAutoLogonFirstInstallBaseline -Snapshot $baseline.snapshot",
    ):
        assert marker in text, marker
    assert "function Test-SasS4UCleanBaseline" not in text


def test_exact_cleanup_profiles_are_scoped_and_probe_recovery_selects_probe_only() -> None:
    cleanup = read(CLEANUP)
    recovery = read(RECOVERY)
    for marker in (
        "ValidateSet('FullS4U','ProbeOnly')",
        "NW_AutoLogon_Setup_x64.exe",
        "s4u-probe-worker.ps1",
        "s4u-probe-result.json",
        "s4u-install-worker.ps1",
        "s4u-install-result.json",
        "outside the $AllowedArtifactProfile cleanup profile; refusing cleanup",
        "exact_autologon_s4u_run_root_only",
        "Remove-Item -LiteralPath `$root -Recurse -Force",
    ):
        assert marker in cleanup, marker
    assert "-AllowedArtifactProfile ProbeOnly" in recovery
    assert "allowed_artifact_profile -ne 'ProbeOnly'" in recovery
    assert "installer_phase_entered = $false" in recovery


def test_exact_interrupted_recovery_never_launches_autologon() -> None:
    text = read(RECOVERY)
    for marker in (
        "Assert-SasNorthwellWifi",
        "S4U_PROBE_CREATE_HANG_RECOVERED",
        "installer_phase_entered = $false",
        "autologon_installer_launched_by_recovered_transaction = $false",
        "Remove-SasExactRemoteAutoLogonRunRoot.ps1",
        "'/Query'",
        "ConfirmRecovery",
        "AllowedArtifactProfile ProbeOnly",
    ):
        assert marker in text, marker
    for forbidden in (
        "Invoke-SasAutoLogonKerberosS4UPilot.ps1",
        "Invoke-SasAutoLogonS4URestartDeployment.ps1",
        "s4u-install-worker.ps1' -Destination",
    ):
        assert forbidden not in text, forbidden


def test_operator_progress_is_persisted_across_all_required_stages() -> None:
    pilot = read(PILOT)
    restart = read(RESTART)
    assert "progress_checkpoint.json" in pilot
    assert "progress_history.jsonl" in pilot
    for number, name in (
        (1, "transport preflight"),
        (2, "canonical software source resolution"),
        (3, "source CIFS ticket"),
        (4, "baseline capture"),
        (5, "baseline eligibility"),
        (6, "final-step gate"),
        (7, "source hash"),
        (8, "staging/hash verification"),
        (17, "after-state capture"),
        (18, "staging cleanup"),
    ):
        assert f"-Number {number} -Name '{name}'" in pilot
    for marker in (
        'Name "$Mode task create"',
        'Name "$Mode task run"',
        'Name "$Mode result"',
        'Name "$Mode cleanup"',
    ):
        assert marker in pilot, marker
    for number, name in (
        (19, "restart handoff"),
        (20, "offline observation"),
        (21, "online observation"),
        (22, "restart-task cleanup"),
    ):
        assert f"-Number {number} -Name '{name}'" in restart


def test_restart_complete_requires_full_cleanup_and_observation_proof() -> None:
    text = read(RESTART)
    for marker in (
        "AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED",
        "$result.status = 'COMPLETED'",
        "$result.autologon_applied = $true",
        "$result.restart_offline_observed",
        "$result.restart_online_observed",
        "$result.automatic_reboot_performed",
        "$result.restart_task_cleanup_verified",
    ):
        assert marker in text, marker


def test_default_password_value_is_never_collected_or_serialized() -> None:
    text = (read(PILOT) + "\n" + read(RESTART) + "\n" + read(RECOVERY)).lower()
    assert "default_password_value_collected = $false" in text
    for forbidden in (
        "get-credential",
        "pscredential",
        "securestring",
        "getvalue('defaultpassword'",
        '"/rp"',
        "'/rp'",
    ):
        assert forbidden not in text, forbidden


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: AutoLogon S4U field hardening contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
