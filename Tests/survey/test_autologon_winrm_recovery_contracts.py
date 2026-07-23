#!/usr/bin/env python3
"""Static contracts for the AutoLogon WinRM-blocker recovery lane."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "scripts" / "SasAutoLogonSmbStateRecovery.psm1"
ORCHESTRATOR = ROOT / "scripts" / "Invoke-SasAutoLogonWinRmRecovery.ps1"
STARTER = ROOT / "scripts" / "Start-SasAutoLogonWinRmRecovery.ps1"
CMD = ROOT / "Recover-AutoLogonWinRmBlocker.cmd"
DOC = ROOT / "docs" / "AUTOLOGON_WINRM_BLOCKER_RECOVERY.md"
PESTER = ROOT / "Tests" / "Pester" / "AutoLogonWinRmRecovery.Tests.ps1"
WORKFLOW = ROOT / ".github" / "workflows" / "autologon-winrm-recovery.yml"


def read(path: Path) -> str:
    assert path.is_file(), f"missing WinRM recovery surface: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_required_recovery_surfaces_exist() -> None:
    for path in (MODULE, ORCHESTRATOR, STARTER, CMD, DOC, PESTER, WORKFLOW):
        assert path.is_file(), f"missing WinRM recovery surface: {path.relative_to(ROOT)}"


def test_smb_state_collector_uses_fresh_closed_transport_authority() -> None:
    text = read(MODULE)
    for marker in (
        "Read-SasDeploymentTransportPreflight",
        "kerberos_smb_task_ready",
        "kerberos_smb_task",
        "State recovery requires the exact authorized FQDN",
        "[switch]$AllowNetworkActivity",
        "[switch]$AllowTargetMutation",
        "selected_before_mutation = $true",
    ):
        assert marker in text, f"missing transport contract: {marker}"
    assert "silent_fallback" not in text, "state collector must not implement silent fallback"


def test_smb_state_worker_is_read_only_and_password_safe() -> None:
    text = read(MODULE)
    for marker in (
        "Test-RegistryValueNameSafe -Path $winlogonPath -Name 'DefaultPassword'",
        "default_password_value_collected = $false",
        "CurrentVersion\\Uninstall",
        "WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
        "configuration_mutation_performed = $false",
        "software_mutation_performed = $false",
        "read_only_state_collection_via_kerberos_smb_task",
    ):
        assert marker in text, f"missing read-only state contract: {marker}"

    lowered = text.lower()
    for forbidden in (
        "get-registryvaluesafe -path $winlogonpath -name 'defaultpassword'",
        "enable-psremoting",
        "winrm quickconfig",
        "set-itemproperty",
        "new-itemproperty",
        "remove-itemproperty",
        "restart-computer",
    ):
        assert forbidden not in lowered, f"forbidden recovery behavior: {forbidden}"


def test_smb_state_lifecycle_verifies_identity_result_and_teardown() -> None:
    text = read(MODULE)
    for marker in (
        "S-1-5-18",
        "source_sha256",
        "target_sha256",
        "hash_verified",
        "nonce",
        "Test-SasAutoLogonRecoveryWorkerResult",
        "result_retrieval.succeeded",
        "'/Delete','/S',$ComputerName",
        "'/Query','/S',$ComputerName",
        "task.absent_verified",
        "run_root_deletion_succeeded",
        "task_remaining",
        "run_root_remaining",
        "Invoke-SasAutoLogonSmbStateCaptureFixture",
    ):
        assert marker in text, f"missing lifecycle contract: {marker}"


def test_recovery_orchestrator_preserves_run_and_prevents_duplicate_install() -> None:
    text = read(ORCHESTRATOR)
    for marker in (
        "survey\\output\\runs\\autologon-proof",
        "exactly one preserved validated deployment request",
        "one target",
        "Get-SasExistingDeploymentEvidence",
        "software_install_summary.json",
        "smb_task_transport_result_*.json",
        "duplicate install",
        "recovery",
    ):
        assert marker.lower() in text.lower(), f"missing preservation contract: {marker}"


def test_recovery_orchestrator_runs_certified_smb_path_only() -> None:
    text = read(ORCHESTRATOR)
    for marker in (
        "Test-SasSoftwareDeploymentTransport.ps1",
        "-TransportIntent kerberos_smb_task",
        "Invoke-SasSoftwareDeploymentTransportLiveCert.ps1",
        "LIVE CERT PASS",
        "Invoke-SasValidatedSoftwareDeployment.ps1",
        "-Transport SmbScheduledTask",
        "Invoke-SasAutoLogonSmbStateCapture",
        "collector_cleanup_verified",
        "deployment_cleanup_verified",
    ):
        assert marker in text, f"missing canonical recovery step: {marker}"

    lowered = text.lower()
    for forbidden in (
        "enable-psremoting",
        "winrm quickconfig",
        "set-wsman",
        "new-pssession",
        "invoke-command",
        "restart-computer",
        "-credential",
    ):
        assert forbidden not in lowered, f"forbidden recovery implementation: {forbidden}"


def test_recovery_classifications_and_proof_ceiling_are_explicit() -> None:
    text = read(ORCHESTRATOR)
    for marker in (
        "ALREADY_CONFIGURED_RUNTIME_PENDING",
        "RECOVERED_DEPLOYMENT_SUCCEEDED_RUNTIME_PENDING",
        "RECOVERED_DEPLOYMENT_STATE_REVIEW",
        "RECOVERY_BLOCKED_EXISTING_DEPLOYMENT_EVIDENCE",
        "RECOVERY_TRANSPORT_BLOCKED",
        "RECOVERY_CLEANUP_REVIEW_REQUIRED",
        "runtime_proof_pending",
        "automatic_reboot_performed = $false",
        "winrm_enabled_or_modified = $false",
        "Reboot, automatic sign-in, current-token access, application behavior, and technician acceptance remain unproven",
    ):
        assert marker in text, f"missing recovery classification or proof boundary: {marker}"


def test_technician_launcher_owns_selection_and_acknowledgement() -> None:
    text = read(STARTER)
    for marker in (
        "[ValidateSet('Menu','Recover','OpenLatest')]",
        "No one-target AutoLogon run is eligible",
        "software_install_summary.json",
        "smb_task_transport_result_*.json",
        "Type RECOVER to continue",
        "-AllowNetworkActivity -AllowTargetMutation -ConfirmRecovery -PassThru",
        "It will not enable WinRM or reboot the workstation.",
    ):
        assert marker in text, f"missing technician launcher contract: {marker}"

    assert "Read-Host 'Mode'" not in text
    assert "Invoke-SasAutoLogonStateDelta.ps1 `" not in text


def test_cmd_is_zero_argument_and_repo_relative() -> None:
    text = read(CMD)
    for marker in (
        'if not "%~1"==""',
        'cd /d "%~dp0"',
        "%~dp0scripts\\Start-SasAutoLogonWinRmRecovery.ps1",
        "-Action Menu",
        "does not accept command-line arguments",
        "exit /b %EXITCODE%",
    ):
        assert marker in text, f"missing CMD contract: {marker}"


def test_runbook_forbids_winrm_repair_and_states_proof_limit() -> None:
    text = read(DOC)
    lowered = text.lower()
    for marker in (
        "do **not** run `winrm quickconfig`",
        "recover-autologonwinrmblocker.cmd",
        "exactly one preserved validated deployment request",
        "refuse automatic recovery if software-install or smb deployment evidence already exists",
        "type:",
        "recover",
        "it does **not** prove reboot behavior, automatic sign-in",
        "do not commit it.",
    ):
        assert marker in lowered, f"missing runbook contract: {marker}"


def test_ci_is_fixture_only_and_does_not_persist_credentials() -> None:
    text = read(WORKFLOW)
    for marker in (
        "persist-credentials: false",
        "test_autologon_winrm_recovery_contracts.py",
        "AutoLogonWinRmRecovery.Tests.ps1",
        "FixtureMode",
        "git diff --check",
    ):
        assert marker in text, f"missing CI contract: {marker}"
    assert "AllowNetworkActivity" not in text
    assert "AllowTargetMutation" not in text


def main() -> None:
    tests = [
        test_required_recovery_surfaces_exist,
        test_smb_state_collector_uses_fresh_closed_transport_authority,
        test_smb_state_worker_is_read_only_and_password_safe,
        test_smb_state_lifecycle_verifies_identity_result_and_teardown,
        test_recovery_orchestrator_preserves_run_and_prevents_duplicate_install,
        test_recovery_orchestrator_runs_certified_smb_path_only,
        test_recovery_classifications_and_proof_ceiling_are_explicit,
        test_technician_launcher_owns_selection_and_acknowledgement,
        test_cmd_is_zero_argument_and_repo_relative,
        test_runbook_forbids_winrm_repair_and_states_proof_limit,
        test_ci_is_fixture_only_and_does_not_persist_credentials,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} AutoLogon WinRM recovery contracts")


if __name__ == "__main__":
    main()
