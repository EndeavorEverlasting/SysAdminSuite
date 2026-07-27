#!/usr/bin/env python3
"""Contracts for technician-facing Cybernet/AutoLogon deployment guidance.

Static only: these checks do not contact a target, deploy software, reboot a workstation,
or create runtime proof.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(relative: str) -> str:
    path = ROOT / relative
    assert path.is_file(), f"missing technician guidance surface: {relative}"
    return path.read_text(encoding="utf-8")


def main() -> int:
    launcher = read("scripts/SasPortableLauncher.ps1")
    installer = read("scripts/Install-SasPortableLauncher.ps1")
    start_here = read("START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md")
    tutorial = read("docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md")

    for text in (launcher, installer, start_here, tutorial):
        assert "sas cybernet Deploy" in text
        assert "sas autologon Remote" in text

    for text in (launcher, start_here, tutorial):
        assert "KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING" in text
        assert "TECHNICIAN_OBSERVED_LIVE_RUNTIME" in text
        assert "Start-SasAutoLogonTechnicianRuntimeProof.cmd" in text

    for text in (installer, start_here, tutorial):
        lowered = text.lower()
        assert "reboot/sign-in" in lowered
        assert "not" in lowered
        assert "attended reboot" in lowered
        assert "automatic sign-in" in lowered

    assert "Do not return to fixture/transport testing after the positive S4U pre-reboot state." in launcher
    assert "The work item is not finished" in start_here
    assert "The work item is not finished" in tutorial
    assert "historical six-package LocalSystem" in start_here
    assert "historical six-package" in tutorial
    assert "install/refresh" in installer

    print("PASS: technician deployment guidance contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
