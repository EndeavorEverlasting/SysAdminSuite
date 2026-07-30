#!/usr/bin/env python3
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Invoke-SasCybernetProfiledClinicalCoreDeployment.ps1"
PREFLIGHT = ROOT / "scripts" / "Test-SasCybernetClinicalCoreSources.ps1"
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
    assert "windows powershell" in text or "windowspowershell" in text


def test_core_preserves_autologon_and_profiles_imprivata() -> None:
    text = read(SCRIPT)
    assert "cybernet-clinical-core" in text
    assert "autologon_included = $false" in text
    assert "automatic_reboot_performed = $false" in text
    assert "autologon_state_preserved" in text
    assert "AutoLogon state changed during the clinical-core run." in text
    assert "Worker result did not prove AutoLogon state preservation." in text
    assert "managed_by_this_run=$false" in text or "managed_by_this_run = $false" in text
    assert "profile_before" in text
    assert "profile_after" in text
    assert "Imprivata" in text
    assert "AutoAdminLogon" in text or "auto_admin_logon" in text
    assert "shutdown.exe" not in text


def test_no_reboot_lane_rejects_reboot_initiated_exit() -> None:
    text = read(SCRIPT)
    assert "$exitCode -eq 1641" in text
    assert "initiated an unauthorized reboot" in text
    assert "$exitCode -in @(0,3010)" in text
    assert "$exitCode -in @(0,3010,1641)" not in text
    assert "reboot_required_but_not_performed" in text


def test_native_core_uses_bounded_existing_management_surfaces() -> None:
    text = read(SCRIPT)
    assert "Confirm-SasNorthwellNetwork.ps1" in text
    assert "Resolve-SasCanonicalTargetFqdn" in text
    assert "\\ADMIN$" in text
    assert "\\C$" in text
    assert "schtasks.exe" in text
    assert "Get-FileHash" in text
    assert "Remove-Item -LiteralPath $remoteRunUnc" in text
    assert "Nmap" not in text
    assert "Naabu" not in text
    assert "WinRM" not in text


def test_sources_are_complete_before_target_staging_and_bundles_use_folder_authority() -> None:
    text = read(SCRIPT)
    source_preflight = text.index("SOURCE PREFLIGHT READY")
    target_access = min(text.index('"\\\\$target\\C$"'), text.index('"\\\\$target\\ADMIN$"'))
    assert source_preflight < target_access
    assert "all_files_recursive_from_approved_bundle_folder" in text
    assert "Get-ChildItem -LiteralPath $sourceFolder -Recurse -File" in text
    assert "tracked_staged_files_only" in text
    assert "source_manifest.json" in text


def test_standalone_source_preflight_never_contacts_target() -> None:
    text = read(PREFLIGHT)
    assert "target_contact_performed = $false" in text
    assert "target_mutation_performed = $false" in text
    assert "all_files_recursive_from_approved_bundle_folder" in text
    assert "tracked_staged_files_only" in text
    assert "Get-FileHash" in text
    assert "CYBERNET_CLINICAL_CORE_SOURCES_READY" in text
    assert "CYBERNET_CLINICAL_CORE_SOURCES_INCOMPLETE" in text
    assert "\\C$" not in text
    assert "\\ADMIN$" not in text
    assert "schtasks.exe" not in text


def test_operator_launchers_preflight_before_deploying() -> None:
    for launcher in (LAUNCHER, COMPAT_LAUNCHER):
        cmd = read(launcher)
        assert "Test-SasCybernetClinicalCoreSources.ps1" in cmd
        assert "SOURCE PREFLIGHT FAILED" in cmd
        assert cmd.index("Test-SasCybernetClinicalCoreSources.ps1") < cmd.index("Invoke-SasCybernetProfiledClinicalCoreDeployment.ps1")
    sas = read(SAS)
    assert "sas cybernet Core HOST" in sas
    assert "Deploy-CybernetProfiledClinicalCore.cmd" in sas
    assert "Git Bash or Python" in sas


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
