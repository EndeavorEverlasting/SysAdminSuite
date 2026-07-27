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
        assert "restart" in text.lower()

    for text in (launcher, start_here, tutorial):
        assert "AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED" in text
        assert "CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED" in text

    for text in (start_here, tutorial):
        lowered = text.lower()
        assert "autologon" in lowered and "last" in lowered
        assert "automatic" in lowered and "restart" in lowered
        assert "fixture" in lowered and "live-cert" in lowered
        assert "not a prerequisite" in lowered or "not required" in lowered
        assert "runtime proof" in lowered

    assert "restart included" in installer
    assert "Fixture/live-cert/runtime-proof loops are NOT prerequisites" in launcher
    assert "historical six-package LocalSystem" in start_here
    assert "historical six-package" in tutorial
    assert "install/refresh" in installer

    print("PASS: technician deployment guidance contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
