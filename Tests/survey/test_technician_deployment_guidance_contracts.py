#!/usr/bin/env python3
"""Contracts for technician-facing Cybernet/AutoLogon deployment guidance.

Static only: these checks do not contact a target, deploy software, reboot a workstation,
or create runtime proof.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def read(relative: str) -> str:
    path = ROOT / relative
    require(path.is_file(), f"missing technician guidance surface: {relative}")
    return path.read_text(encoding="utf-8")


def main() -> int:
    launcher = read("scripts/SasPortableLauncher.ps1")
    installer = read("scripts/Install-SasPortableLauncher.ps1")
    start_here = read("START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md")
    tutorial = read("docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md")

    surfaces = {
        "launcher": launcher,
        "installer": installer,
        "start-here": start_here,
        "tutorial": tutorial,
    }
    for name, text in surfaces.items():
        require("sas cybernet Deploy" in text, f"{name} missing full Cybernet deployment command")
        require("sas autologon Remote" in text, f"{name} missing AutoLogon-only deployment command")
        require("restart" in text.lower(), f"{name} missing required restart guidance")

    for name, text in (("launcher", launcher), ("start-here", start_here), ("tutorial", tutorial)):
        require("AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED" in text, f"{name} missing AutoLogon restart-complete classification")
        require("CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED" in text, f"{name} missing full software restart-complete status")

    for name, text in (("start-here", start_here), ("tutorial", tutorial)):
        lowered = text.lower()
        require("autologon" in lowered and "last" in lowered, f"{name} does not require AutoLogon last")
        require("automatic" in lowered and "restart" in lowered, f"{name} does not describe automatic restart")
        require("fixture" in lowered and "live-cert" in lowered, f"{name} does not reject diagnostic-only substitutes")
        require("not a prerequisite" in lowered or "not required" in lowered, f"{name} makes extra proof look mandatory for deployment")
        require("runtime proof" in lowered, f"{name} does not preserve optional runtime-proof guidance")

    require("restart included" in installer, "installer output does not advertise restart-complete deployment")
    require(
        "Fixture/live-cert/runtime-proof loops are NOT prerequisites" in launcher,
        "portable launcher does not explicitly prevent test loops from delaying deployment",
    )
    require("historical six-package LocalSystem" in start_here, "start-here does not preserve the blocked LocalSystem boundary")
    require("historical six-package" in tutorial, "tutorial does not preserve the blocked LocalSystem boundary")
    require("install/refresh" in installer, "operator command refresh behavior is not documented")

    print("PASS: technician deployment guidance contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
