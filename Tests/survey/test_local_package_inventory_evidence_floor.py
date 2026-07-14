#!/usr/bin/env python3
"""Dependency-free safety contracts for local package inventory evidence."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCANNER = ROOT / "scripts" / "Get-SasLocalPackageInventory.ps1"
SCHEMA = ROOT / "schemas" / "harness" / "local-package-inventory.schema.json"
FIXTURE = ROOT / "Tests" / "Fixtures" / "local-package-inventory.fixture.json"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    scanner = SCANNER.read_text(encoding="utf-8")
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))

    require(
        schema["properties"]["scan_root"]["enum"]
        == ["fixture-only", "operator-local-reference"],
        "scan_root must be a redacted identity, never an operator-local path",
    )
    require("[string]$ScanPath =" not in scanner, "ScanPath must not have a local default")
    require("ScanPath is required unless FixtureOnly" in scanner, "missing explicit scan-root gate")
    require("@('/qn', '/norestart')" not in scanner, "MSI arguments must not be guessed")
    require('@("/qn", "/norestart")' not in scanner, "MSI arguments must not be guessed")

    for forbidden in ("Start-Process", "Invoke-Expression", "Invoke-Command", "msiexec"):
        require(
            not re.search(rf"(?i)\b{re.escape(forbidden)}(?:\.exe)?\b", scanner),
            f"forbidden execution primitive: {forbidden}",
        )

    require(fixture["scan_root"] == "fixture-only", "fixture root must be redacted")
    require(fixture["schema_version"] == "sas-local-package-inventory/v1", "unexpected fixture schema")
    require(len(fixture["packages"]) >= 4, "fixture must cover the observed package families")

    for package in fixture["packages"]:
        path = package["relative_path"]
        require(not re.match(r"^[A-Za-z]:", path), f"drive-qualified fixture path: {path}")
        require(not re.match(r"^[/\\]{2}", path), f"UNC fixture path: {path}")
        require(not re.search(r"(^|[/\\])\.\.([/\\]|$)", path), f"traversal fixture path: {path}")
        require(package["installer_arguments"] is None, f"unverified arguments in fixture: {path}")
        require(re.fullmatch(r"[a-f0-9]{64}", package["sha256"]) is not None, f"invalid fixture hash: {path}")

    auto = [
        package
        for package in fixture["packages"]
        if package["classification"] == "requires_physical_cybernet"
    ]
    require(len(auto) == 1, "fixture must contain exactly one physical-Cybernet-only package")
    require(
        auto[0]["authenticode"] == {"status": "NotSigned", "signer": None},
        "AutoLogon fixture must not fabricate signature evidence",
    )
    require("autologon" in auto[0]["dangerous_indicators"], "AutoLogon mutation indicator missing")
    require("reboot" in auto[0]["dangerous_indicators"], "AutoLogon reboot indicator missing")

    print("PASS: local package inventory evidence floor")


if __name__ == "__main__":
    main()
