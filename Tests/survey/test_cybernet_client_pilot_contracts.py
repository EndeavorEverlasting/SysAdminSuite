#!/usr/bin/env python3
"""Dependency-free contracts for the one-command Cybernet pilot surface."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "Run-CybernetClientConfiguration.cmd"
PILOT = ROOT / "Hardware/Cybernet/Invoke-CybernetClientPilot.ps1"
GUIDE = ROOT / "docs/tutorials/CYBERNET_CLIENT_PILOT.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def test_root_cmd_owns_the_pilot_surface() -> None:
    launcher = read(LAUNCHER)
    for marker in (
        'if /I "%MODE%"=="Pilot" goto pilot',
        "Invoke-CybernetClientPilot.ps1",
        "Preferred one-target pilot",
        "deployment dry run",
        "harmless transport live cert",
        "PILOT_COMPLETE_TECHNICIAN_ACCEPTANCE_REQUIRED",
        "Cybernet profile only",
    ):
        assert marker in launcher
    assert 'if not "%~3"==""' in launcher
    assert "-ExecutionPolicy Bypass" not in launcher


def test_pilot_orders_proof_before_production() -> None:
    pilot = read(PILOT)
    ordered_markers = (
        "Invoke-SasPilotConfigurationMode -Mode Plan",
        "$preflight = & $preflightScript",
        "$liveCert = & $liveCertScript",
        "[string]$liveCert.disposition -ne 'LIVE CERT PASS'",
        "$PSCmdlet.ShouldProcess",
        "Invoke-SasPilotConfigurationMode -Mode Apply",
        "Invoke-SasPilotConfigurationMode -Mode Validate",
    )
    positions = [pilot.index(marker) for marker in ordered_markers]
    assert positions == sorted(positions)


def test_pilot_fails_closed_at_each_boundary() -> None:
    pilot = read(PILOT)
    for marker in (
        "Pilot requires one explicitly authorized fully qualified DNS name",
        "kerberos_smb_task_ready",
        "Stop before target mutation or production deployment",
        "Stop before production deployment",
        "Stop; do not bypass or blindly retry the failed gate",
        "SupportsShouldProcess = $true",
        "ConfirmImpact = 'High'",
        "-AllowNetworkActivity",
        "-AllowTargetMutation",
        "-Confirm:$false",
        "LIVE_CERT_PASS_PRODUCTION_NOT_RUN",
        "PILOT_COMPLETE_TECHNICIAN_ACCEPTANCE_REQUIRED",
        "autologon_position = 'last'",
        "automatic_reboot_performed = $false",
    ):
        assert marker in pilot
    for forbidden in (
        "-Credential",
        "Get-Credential",
        "Restart-Computer",
        "shutdown.exe",
        "Invoke-CybernetComPortAutoFix.ps1",
        "-ExecutionPolicy Bypass",
    ):
        assert forbidden not in pilot


def test_technician_guide_is_one_command_and_profile_safe() -> None:
    guide = read(GUIDE)
    for marker in (
        "Run-CybernetClientConfiguration.cmd Pilot",
        "Do not reconstruct the workflow from individual scripts",
        "shared or normal user-login workstation",
        "unknown, ambiguous, or conflicting",
        "Deployment dry run",
        "Read-only live preflight",
        "Harmless live certification",
        "Production confirmation",
        "AutoLogon must remain last",
        "PILOT_COMPLETE_TECHNICIAN_ACCEPTANCE_REQUIRED",
        "separately authorized reboot",
    ):
        assert marker in guide


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: Cybernet client pilot contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
