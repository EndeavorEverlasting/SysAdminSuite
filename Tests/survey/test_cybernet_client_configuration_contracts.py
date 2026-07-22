#!/usr/bin/env python3
"""Dependency-free contracts for the composed Cybernet client configuration."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROFILE = ROOT / "Config/cybernet-client-preferences.json"
PACKAGE_SETS = ROOT / "configs/software-packages/windows-native-package-sets.json"
SCRIPT = ROOT / "Hardware/Cybernet/Invoke-CybernetClientConfiguration.ps1"
LAUNCHER = ROOT / "Run-CybernetClientConfiguration.cmd"
GUIDE = ROOT / "docs/tutorials/CYBERNET_CLIENT_CONFIGURATION.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def load(path: Path) -> dict:
    return json.loads(read(path))


def test_profile_matches_client_preferences() -> None:
    profile = load(PROFILE)
    assert profile["schema_version"] == "sas-cybernet-client-preferences/v1"
    hardware = profile["hardware"]
    assert hardware["standby_ac_minutes"] == 0
    assert hardware["standby_dc_minutes"] == 0
    assert hardware["hibernate_ac_minutes"] == 0
    assert hardware["hibernate_dc_minutes"] == 0
    assert hardware["physical_power_button_action"] == "do_nothing"
    assert hardware["display_button_control"]["vcp_code"] == "0xCA"
    assert hardware["display_button_control"]["desired_value"] == "0x0303"
    assert hardware["ready_com_ports"] == ["COM1", "COM2", "COM3", "COM4"]
    assert hardware["repairable_com_ports"] == ["COM3", "COM4", "COM5", "COM6"]
    assert profile["workflow"]["pilot_target_count"] == 1
    assert profile["workflow"]["maximum_target_count"] == 25
    assert profile["workflow"]["automatic_reboot_forbidden"] is True
    assert profile["workflow"]["apply_order"] == [
        "hardware_apply_and_validate",
        "approved_software_package_set_install",
        "hardware_post_software_validate",
        "technician_software_acceptance",
    ]


def test_profile_uses_exact_approved_package_set_order() -> None:
    profile = load(PROFILE)
    catalog = load(PACKAGE_SETS)
    package_set = next(
        item for item in catalog["package_sets"]
        if item["id"] == profile["software"]["package_set_id"]
    )
    assert profile["software"]["package_count"] == 6
    assert profile["software"]["package_ids"] == package_set["package_ids"]
    assert package_set["package_ids"][-1] == "autologon"
    enabled = {item["id"]: item["install_enabled"] for item in catalog["packages"]}
    assert all(enabled[package_id] is True for package_id in package_set["package_ids"])


def test_orchestrator_reuses_authoritative_lanes() -> None:
    script = read(SCRIPT)
    for marker in (
        "Invoke-CybernetBatchConfiguration.ps1",
        "bash/apps/sas-install-apps.sh",
        "--package-set",
        "--allow-legacy",
        "hardware-apply",
        "approved-software-install",
        "hardware-post-software-validation",
        "APPLIED_TECHNICIAN_ACCEPTANCE_REQUIRED",
        "HARDWARE_VALIDATED_SOFTWARE_ACCEPTANCE_REQUIRED",
        "technician_software_acceptance.txt",
        "if (@($stages | Where-Object exit_code -ne 0).Count -eq 0)",
    ):
        assert marker in script


def test_orchestrator_fails_closed_and_does_not_bypass_boundaries() -> None:
    script = read(SCRIPT)
    for marker in (
        "[string]$Mode = 'Plan'",
        "Apply requires -AllowTargetMutation",
        "SupportsShouldProcess = $true",
        "--dry-run",
        "automatic_reboot_performed = $false",
        "com_mutation_performed = $false",
        "software_acceptance_required = $true",
        "The client-preference software order does not match the approved package-set catalog",
    ):
        assert marker in script
    for forbidden in (
        "--smb-user",
        "--smb-pass",
        "--smb-domain",
        "Restart-Computer",
        "shutdown.exe",
        "Set-ItemProperty",
        "Invoke-CybernetComPortAutoFix.ps1",
        "-ExecutionPolicy Bypass",
    ):
        assert forbidden not in script


def test_launcher_is_one_target_and_preserves_plan_first() -> None:
    launcher = read(LAUNCHER)
    assert "-Mode Plan" in launcher
    assert "-Mode Apply" in launcher
    assert "-Mode Validate" in launcher
    assert "-AllowTargetMutation" in launcher
    assert 'if not "%~3"==""' in launcher
    assert "-ExecutionPolicy Bypass" not in launcher
    assert "reboots a target" in launcher
    assert "repairs COM ports remotely" in launcher


def test_technician_guide_covers_complete_acceptance() -> None:
    guide = read(GUIDE)
    for marker in (
        "standby and hibernate idle timeouts set to **Never**",
        "physical power button set to **Do nothing**",
        "VCP `0xCA = 0x0303`",
        "approved six-package clinical workstation set",
        "AutoLogon must remain last",
        "Run-CybernetClientConfiguration.cmd Plan",
        "Run-CybernetClientConfiguration.cmd Apply",
        "Run-CybernetClientConfiguration.cmd Validate",
        "COM3,COM4,COM5,COM6",
        "technician_software_acceptance.txt",
        "separately authorized reboot",
    ):
        assert marker in guide


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: Cybernet client configuration contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
