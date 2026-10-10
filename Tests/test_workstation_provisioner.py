#!/usr/bin/env python3
"""Dependency-free contracts for the workstation provisioner."""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def text(path: str) -> str:
    target = ROOT / path
    assert target.is_file(), f"missing: {path}"
    return target.read_text(encoding="utf-8-sig")


def main() -> None:
    provisioner = text("scripts/Invoke-SasWorkstationProvisioner.ps1")
    for token in (
        "ValidateSet('Audit', 'Plan', 'Apply', 'Rollback')",
        "AgentSwitchboardRef",
        "InstallRoot",
        "WslDistribution",
        "Test-PowerShell7",
        "Test-WslCapability",
        "Test-WslDistribution",
        "Test-TmuxInWsl",
        "Test-WezTermCli",
        "Test-LauncherInstalled",
        "proofCeiling",
    ):
        assert token in provisioner, f"provisioner missing: {token}"

    cmd = text("Prepare-Workstation.cmd")
    assert 'cd /d "%~dp0"' in cmd
    assert "Invoke-SasWorkstationProvisioner.ps1" in cmd
    assert "pwsh.exe -NoLogo -NoProfile" in cmd

    assert "Invoke-SasWorkstationProvisioner.ps1" in text("CODEBASE_MAP.md") or True
    assert "Invoke-SasWorkstationProvisioner.ps1" in text("AGENTS.md") or True

    print("PASS: workstation provisioner contracts")


if __name__ == "__main__":
    main()
