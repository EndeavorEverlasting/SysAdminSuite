#!/usr/bin/env python3
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Invoke-SasCybernetProfiledClinicalCoreDeployment.ps1"
RECOVERY = ROOT / "scripts" / "Invoke-SasCybernetCoreRecovery.ps1"
PREFLIGHT = ROOT / "scripts" / "Test-SasCybernetClinicalCoreSources.ps1"
READINESS = ROOT / "scripts" / "Invoke-SasCybernetDeploymentReadiness.ps1"
SESSION = ROOT / "scripts" / "SasOperatorSession.psm1"
CONTEXT = ROOT / "scripts" / "Show-SasOperatorContext.ps1"
EVIDENCE = ROOT / "scripts" / "Show-SasOperatorEvidence.ps1"
REFRESH = ROOT / "scripts" / "Refresh-SasOperatorCommand.ps1"
LAUNCHER = ROOT / "Deploy-CybernetProfiledClinicalCore.cmd"
COMPAT_LAUNCHER = ROOT / "Deploy-CybernetClinicalCore.cmd"
SAS = ROOT / "scripts" / "SasPortableLauncher.ps1"
PROFILE = ROOT / "Config" / "cybernet-client-preferences.json"


def read(path: Path) -> str:
    assert path.is_file(), path
    return path.read_text(encoding="utf-8-sig")


def test_native_core_has_no_python_or_git_bash_dependency() -> None:
    text = read(SCRIPT).lower()
    assert "python3" not in text
    assert "bash.exe" not in text
    assert "git bash" not in text
    assert "windowspowershell" in text or "windows powershell" in text


def test_core_requires_explicit_cybernet_profile_authority() -> None:
    text = read(SCRIPT)
    launcher = read(LAUNCHER)
    assert "[ValidateSet('Cybernet')][string]$EquipmentProfile" in text
    assert "$EquipmentProfile -ne 'Cybernet'" in text
    assert "Config\\cybernet-client-preferences.json" in text
    assert "profile_eligibility_proven=$true" in text
    assert "explicit_tracked_sas_cybernet_core_command" in text
    assert "target_locked=$true" in text
    assert "-EquipmentProfile Cybernet" in launcher
    assert "explicit equipment-profile authority" in launcher


def test_core_preserves_disabled_autologon_and_profiles_imprivata() -> None:
    text = read(SCRIPT)
    assert "package_set_id='cybernet-clinical-core'" in text
    assert "autologon_included=$false" in text
    assert "expected_autologon_state='disabled_preserve_only'" in text
    assert "expected_autologon_enabled=$false" in text
    assert "AutoLogon precondition mismatch" in text
    assert "AutoLogon state changed during the clinical-core run." in text
    assert "AutoLogon final state does not match the disabled-preserve-only expectation." in text
    assert "managed_by_this_run=$false" in text
    assert "observational/external state only" in text
    assert "startup_type" in text
    assert "Get-CimInstance Win32_Service" in text
    assert "automatic_reboot_performed=$false" in text
    assert "shutdown.exe" not in text


def test_no_reboot_lane_rejects_reboot_initiated_exit() -> None:
    text = read(SCRIPT)
    assert "$exitCode -eq 1641" in text
    assert "initiated an unauthorized reboot" in text
    assert "$exitCode -in @(0,3010)" in text
    assert "$exitCode -in @(0,3010,1641)" not in text
    assert "reboot_required_but_not_performed" in text


def test_complete_source_preflight_and_transport_readiness_precede_target_mutation() -> None:
    text = read(SCRIPT)
    preflight_call = text.index("& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $preflightPath")
    source_ready = text.index("[3/7] SOURCES READY 5/5")
    readiness_call = text.index("$readiness=& $readinessPath")
    readiness_ready = text.index("TRANSPORT READY: KERBEROS SMB + TASK")
    admin_access = text.index('$adminRoot="\\\\$target\\ADMIN$"')
    c_access = text.index('$cRoot="\\\\$target\\C$"')
    remote_create = text.index("New-Item -ItemType Directory -Path $remoteRunUnc")
    assert preflight_call < source_ready < readiness_call < readiness_ready
    assert readiness_ready < admin_access < remote_create
    assert readiness_ready < c_access < remote_create
    assert "source_preflight_complete_before_target_contact=$false" in text
    assert "source_preflight_complete_before_target_mutation=$false" in text
    assert "target_contact_performed=$false" in text
    assert "target_mutation_performed=$false" in text
    assert "CYBERNET_DEPLOYMENT_READINESS_READY" in text
    assert "kerberos_smb_task_ready" in text
    readiness = read(READINESS)
    assert "target_mutation_performed = $false" in readiness
    assert "transport_authorization_proven" in readiness


def test_bundle_authority_records_real_inventory_and_drift() -> None:
    text = read(PREFLIGHT)
    assert "all_files_recursive_from_approved_bundle_folder" in text
    assert "Get-ChildItem -LiteralPath $sourceFolder -Recurse -File" in text
    assert "tracked_staged_files_only" in text
    assert "actual_files" in text
    assert "missing_files" in text
    assert "unexpected_files" in text
    assert "inventory_drift" in text
    assert "reported_not_silently_ignored" in text
    assert "target_contact_performed = $false" in text
    assert "target_mutation_performed = $false" in text
    assert "\\C$" not in text
    assert "\\ADMIN$" not in text
    assert "schtasks.exe" not in text


def test_transaction_has_stable_progress_worker_checkpoints_and_exact_cleanup() -> None:
    text = read(SCRIPT)
    for marker in (
        "[1/7] NETWORK READY",
        "[2/7] TARGET LOCKED",
        "[3/7] SOURCES READY 5/5",
        "[4/7] TARGET STAGING HASH VERIFIED",
        "[5/7] SYSTEM INSTALL RUNNING",
        "[6/7] BEFORE/AFTER PROFILE CAPTURED",
        "[7/7] CLEANUP VERIFIED",
        "worker_checkpoint.json",
        "checkpoint_history",
        "Save-Checkpoint -Phase 'PACKAGE_STARTING'",
        "Save-Checkpoint -Phase 'PACKAGE_COMPLETED'",
        "SysAdminSuite-CybernetCore-$runId",
        "Remove-Item -LiteralPath $remoteRunUnc",
        "CYBERNET_PROFILED_CLINICAL_CORE_COMPLETED",
    ):
        assert marker in text, marker
    assert "finally {" in text
    assert "try {" in text
    assert "catch" in text


def test_recovery_is_run_scoped_and_preserves_completed_work() -> None:
    text = read(RECOVERY)
    assert "CYBERNET_PROFILED_CLINICAL_CORE_RECOVERY_VERIFIED" in text
    assert "worker_checkpoint_recovered.json" in text
    assert "worker_result_recovered.json" in text
    assert "completed_package_ids" in text
    assert "recovered_run_id" in text
    assert "ProgramData\\SysAdminSuite\\CybernetProfiledCore\\$RunId" in text
    assert "[regex]::Escape($RunId)" in text
    assert "Remove-Item -LiteralPath $remoteRunUnc" in text
    assert "worker may still be running" in text.lower()
    assert "Remove-Item -LiteralPath \\\\$target\\C$\\ProgramData\\SysAdminSuite" not in text


def test_resume_excludes_proven_completed_packages() -> None:
    text = read(SCRIPT)
    assert "resumed_completed_package_ids" in text
    assert "$package.id -notin $priorCompletedIds" in text
    assert "preserved_prior_success_not_reexecuted" in text
    assert "installer will NOT repeat" in text


def test_machine_local_operator_session_is_persistent_and_terminal_agnostic() -> None:
    text = read(SESSION)
    assert "operator-session.json" in text
    assert "sas-operator-session/v1" in text
    assert "$env:LOCALAPPDATA" in text
    for field in (
        "repo_root", "repo_head", "launcher_head", "current_network_classification",
        "last_network_classification", "last_network_label", "current_terminal",
        "target_input", "target_fqdn", "target_locked", "equipment_profile",
        "profile_eligibility_proven", "profile_eligibility_source", "deployment_lane",
        "package_set", "expected_autologon_state", "imprivata_disposition",
        "latest_run_id", "latest_status", "cleanup_outstanding",
        "target_mutation_performed", "package_execution_started", "completed_package_ids",
        "next_required_network", "next_command", "evidence_path",
    ):
        assert field in text, field
    assert "Values.ContainsKey('current_network_classification')" in text
    assert "field-ready*" in text
    assert "PowerShell:" not in text


def test_context_next_and_refresh_recover_state_without_target_literal() -> None:
    context = read(CONTEXT)
    refresh = read(REFRESH)
    sas = read(SAS)
    assert "Sync-SasOperatorSessionFromEvidence" in context
    assert "-TargetFqdn $targetFilter" in context
    assert "Previous network:" in context
    assert "NEXT NETWORK:" in context and "NEXT COMMAND:" in context
    assert "Sync-SasOperatorSessionFromEvidence" in refresh
    assert "SAS_OPERATOR_REFRESH_READY" in refresh
    assert "PROTECTED NORTHWELL" in refresh
    assert "sas cybernet Core $nextTarget" in refresh
    assert "sas context" in sas and "sas next" in sas
    assert "sas cybernet Recover HOST" in sas
    assert "NETWORK REQUIRED: GUEST / INTERNET" in sas
    assert "NETWORK REQUIRED: PROTECTED NORTHWELL" in read(LAUNCHER)
    for text in (context, refresh, sas):
        assert "WPJ075OPR046" not in text
        assert "pa_rperez26" not in text


def test_evidence_surfaces_profiled_core_boundary_and_next_action() -> None:
    text = read(EVIDENCE)
    assert "cybernet_profiled_clinical_core_result.json" in text
    assert "CYBERNET_PROFILED_CLINICAL_CORE_COMPLETED" in text
    assert "ACTION_REQUIRED" in text
    for field in ("run_id", "target", "phase", "checkpoint", "completed_packages", "failed_package", "cleanup_succeeded"):
        assert field in text, field
    assert "field-ready*" in text
    assert "NEXT NETWORK:" in text
    assert "NEXT COMMAND:" in text


def test_operator_launchers_route_deploy_through_one_transaction() -> None:
    cmd = read(LAUNCHER)
    compat = read(COMPAT_LAUNCHER)
    sas = read(SAS)
    assert "Invoke-SasCybernetProfiledClinicalCoreDeployment.ps1" in cmd
    assert "-EquipmentProfile Cybernet" in cmd
    assert "Test-SasCybernetClinicalCoreSources.ps1" not in cmd
    assert "Deploy-CybernetProfiledClinicalCore.cmd" in compat
    assert "sas cybernet Core HOST" in sas
    assert "Deploy-CybernetProfiledClinicalCore.cmd" in sas


def test_profile_models_conditional_imprivata_and_autologon() -> None:
    profile = json.loads(read(PROFILE))
    lane = profile["software"]["deployment_lanes"]["profiled_clinical_core"]
    assert lane["package_set_id"] == "cybernet-clinical-core"
    assert lane["package_count"] == 5
    assert lane["git_bash_required"] is False
    assert lane["python_required"] is False
    assert lane["automatic_reboot"] is False
    assert lane["autologon_behavior"] == "observe_only_do_not_enable_disable_or_repair"
    obs = profile["software"]["conditional_observations"]
    assert obs["imprivata"]["managed_by_sysadminsuite_clinical_core"] is False
    assert obs["imprivata"]["capture_before_and_after"] is True
    assert obs["autologon"]["core_lane_mutation"] == "forbidden"


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: Cybernet profiled clinical-core contracts ({len(tests)} groups)")