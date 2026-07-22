#!/usr/bin/env python3
"""Dependency-free contracts for the Cybernet hardware batch module.

These tests inspect tracked implementation and safety boundaries. They do not
contact a target, invoke DDC/CI, change power policy, edit COM mappings, or reboot.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HARDWARE = ROOT / "Hardware" / "Cybernet"


def read(name: str) -> str:
    path = HARDWARE / name
    assert path.is_file(), f"missing Cybernet hardware file: {path}"
    return path.read_text(encoding="utf-8")


def test_expected_module_surface() -> None:
    expected = {
        "CybernetHardware.Common.psm1",
        "Invoke-CybernetStage.ps1",
        "Invoke-CybernetBatchConfiguration.ps1",
        "Disable-PrivacyButton.ps1",
        "Enable-PrivacyButton.ps1",
        "Set-NoSleep.ps1",
        "Set-PowerButtonDoNothing.ps1",
        "COM-Port-Check.ps1",
        "PostInstall-Validation.ps1",
        "README.md",
    }
    missing = sorted(name for name in expected if not (HARDWARE / name).is_file())
    assert not missing, f"missing expected module files: {missing}"
    assert (ROOT / "Run-CybernetBatchConfiguration.cmd").is_file()


def test_privacy_wrappers_use_canonical_ddcci_authority() -> None:
    disable = read("Disable-PrivacyButton.ps1")
    enable = read("Enable-PrivacyButton.ps1")
    for content in (disable, enable):
        assert "Invoke-SasCybernetDisplayButtonControl.ps1" in content
        assert "-AllowTargetMutation" in content
        assert "SupportsShouldProcess = $true" in content
        for forbidden in ("Set-ItemProperty", "reg.exe add", "Register-ScheduledTask", "New-Service"):
            assert forbidden not in content
    assert "Operation = 'Apply'" in disable
    assert "0x0303" in disable
    assert "Operation = 'Restore'" in enable
    assert "RestoreManifest" in enable


def test_power_button_wrapper_reuses_merged_authority() -> None:
    content = read("Set-PowerButtonDoNothing.ps1")
    assert "Invoke-SasCybernetPowerHardening.ps1" in content
    assert "SupportsShouldProcess = $true" in content
    assert "-AllowTargetMutation" in content
    assert "UIBUTTON_ACTION" not in content


def test_no_sleep_is_bounded_and_verifies_exact_settings() -> None:
    content = read("Set-NoSleep.ps1")
    for marker in (
        "29f6c1db-86da-48c5-9fdb-f2b67b1f44da",
        "9d7815a6-7ee4-497e-8888-515a05f02364",
        "'/setacvalueindex'",
        "'/setdcvalueindex'",
        "APPLIED_VERIFIED",
        "-AllowTargetMutation",
        "ShouldProcess",
        "FixtureMode",
    ):
        assert marker in content
    for forbidden in ("SUB_VIDEO", "DISKIDLE", "LIDACTION", "SetVCPFeature"):
        assert forbidden not in content


def test_com_batch_is_read_only_and_routes_local_repair() -> None:
    content = read("COM-Port-Check.ps1")
    common = read("CybernetHardware.Common.psm1")
    assert "Get-CimInstance -ClassName Win32_SerialPort" in content
    assert "HKLM:\\HARDWARE\\DEVICEMAP\\SERIALCOMM" in content
    assert "COM_AUTOFIX_ELIGIBLE_LOCAL_ONLY" in common
    assert "Run-CybernetComPortAutoFix-DryRun.cmd" in content
    for forbidden in (
        "Set-ItemProperty",
        "reg.exe add",
        "Restart-Computer",
        "Invoke-CybernetComPortAutoFix.ps1",
        "AllowTargetMutation",
    ):
        assert forbidden not in content


def test_postinstall_validation_is_read_only_and_complete() -> None:
    content = read("PostInstall-Validation.ps1")
    for marker in (
        "standbyIdle",
        "hibernateIdle",
        "powerButtonAction",
        "Get-CimInstance -ClassName Win32_SerialPort",
        "Invoke-SasCybernetDisplayButtonControl.ps1",
        "VCP_CA_0X0303_VERIFIED",
        "COM_PORTS_READY",
        "target_mutation_performed = $false",
    ):
        assert marker in content
    for forbidden in ("/setacvalueindex", "/setdcvalueindex", "Set-ItemProperty", "Restart-Computer"):
        assert forbidden not in content


def test_batch_defaults_to_plan_and_composes_exact_stages() -> None:
    content = read("Invoke-CybernetBatchConfiguration.ps1")
    runner = read("Invoke-CybernetStage.ps1")
    assert "[string]$Mode = 'Plan'" in content
    assert "Set-NoSleep.ps1" in content
    assert "Set-PowerButtonDoNothing.ps1" in content
    assert "Disable-PrivacyButton.ps1" in content
    assert "PostInstall-Validation.ps1" in content
    assert "LOCAL_ONLY_EXISTING_AUTOFIX" in content
    assert "com_mutation_performed = $false" in content
    assert "ParameterJson" in runner
    assert "& $ScriptPath @parameters" in runner
    assert "Invoke-CybernetComPortAutoFix.ps1" not in content


def test_launcher_is_one_target_and_does_not_bypass_policy() -> None:
    launcher = (ROOT / "Run-CybernetBatchConfiguration.cmd").read_text(encoding="utf-8")
    assert "-Mode Plan" in launcher
    assert "-Mode Apply" in launcher
    assert "-Mode Validate" in launcher
    assert "-AllowTargetMutation" in launcher
    assert "-ExecutionPolicy Bypass" not in launcher
    assert 'if not "%~3"==""' in launcher


def test_docs_record_authority_and_proof_ceiling() -> None:
    docs = read("README.md")
    for marker in (
        "MCCS 2.2 VCP code `0xCA`",
        "`0x0303`",
        "local-only",
        "one authorized target",
        "Fixture and CI passes",
        "Run-CybernetComPortAutoFix-DryRun.cmd",
    ):
        assert marker in docs


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: Cybernet hardware batch contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
