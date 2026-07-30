#!/usr/bin/env python3
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Invoke-SasCybernetProfiledClinicalCoreDeployment.ps1"
LAUNCHER = ROOT / "Deploy-CybernetProfiledClinicalCore.cmd"
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
    assert "managed_by_this_run = $false" in text
    assert "profile_before" in text
    assert "profile_after" in text
    assert "Imprivata" in text
    assert "AutoAdminLogon" in text
    assert "shutdown.exe" not in text


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


def test_operator_surface_exposes_core_lane() -> None:
    cmd = read(LAUNCHER)
    sas = read(SAS)
    assert "Invoke-SasCybernetProfiledClinicalCoreDeployment.ps1" in cmd
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
