#!/usr/bin/env python3
"""Contracts for the CMD-first Cybernet identity probe."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CMD = ROOT / "Probe-Cybernet.cmd"
CANARY = ROOT / "survey" / "sas-cybernet-canary.ps1"
REFRESH = ROOT / "scripts" / "Refresh-SasOperatorCommand.ps1"
DOC = ROOT / "docs" / "CYBERNET_LOW_NOISE_CANARY.md"
MAP = ROOT / "harness" / "maps" / "CYBERNET_HARDWARE_IDENTITY_MAP.md"
START = ROOT / "START-HERE-CYBERNET-NEURON-SURVEY.md"


def text(path: Path) -> str:
    assert path.is_file(), f"missing Cybernet probe contract surface: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def main() -> None:
    cmd = text(CMD)
    canary = text(CANARY)
    refresh = text(REFRESH)

    # The technician surface asks the real question rather than advertising a generic scan.
    for marker in (
        "Question: Is each explicit candidate a Windows client workstation",
        "model + serial for approved Cybernet-reference comparison",
        "135 + 445 open       = metadata candidate only",
        "ProductType = 1      = Windows client workstation only",
        "Cybernet confirmed   = only after approved reference comparison",
    ):
        assert marker in cmd, marker

    # Currentness is established before the first possible target-facing canary.
    refresh_call = cmd.index('Invoke-SasNetworkAwareField.ps1\" refresh')
    refreshed_reentry = cmd.index('call \"C:\\SASAL\\Probe-Cybernet.cmd\"')
    canary_call = cmd.index('survey\\sas-cybernet-canary.ps1\" %*')
    assert refresh_call < refreshed_reentry < canary_call
    assert 'set "SAS_CYBERNET_PROBE_REFRESHED=1"' in cmd
    assert 'set "SAS_EXIT=!ERRORLEVEL!"' in cmd
    assert 'endlocal & exit /b %SAS_EXIT%' in cmd

    # Refresh is repository-owned Git synchronization, not an ad-hoc pull from the caller worktree.
    assert "sync-cache" in refresh
    assert "field-ready" in refresh
    assert "fetch" in refresh
    assert "origin/$refreshBranch" in refresh
    assert "No target contact or target mutation occurs in this script." in refresh
    assert "git pull" not in cmd.lower()
    assert "git fetch" not in cmd.lower()

    # The probe spends packets only through the bounded canary, not through a generic discovery lane.
    assert "sas-network-preflight.ps1" in canary
    assert "-Ports @(135,445)" in canary
    assert "$MaxTargets = 5" in canary
    assert "Win32_OperatingSystem" in canary
    assert "ProductType" in canary
    assert "Win32_ComputerSystem" in canary
    assert "Win32_BIOS" in canary
    assert "CONFIRMED_CYBERNET" not in canary
    for forbidden in ("nmap", "naabu", "9100", "5985", "5986"):
        assert forbidden not in cmd.lower(), forbidden

    # Operator docs must make CMD the front door and preserve the proof ceiling.
    for path in (DOC, MAP, START):
        body = text(path)
        assert "Probe-Cybernet.cmd" in body, f"{path.relative_to(ROOT)} missing CMD front door"
        assert "approved" in body.lower() and "reference" in body.lower()

    print("PASS: Cybernet CMD probe refreshes before target contact and asks the bounded identity question")


if __name__ == "__main__":
    main()
