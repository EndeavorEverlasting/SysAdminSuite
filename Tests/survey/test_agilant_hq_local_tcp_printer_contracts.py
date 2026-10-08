#!/usr/bin/env python3
"""Agilant HQ local TCP printer mapping regression guardrails.

Static repository and contract validation; never contacts a printer.
Live functional certification remains a separate Windows/field gate.
"""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8-sig")


def check_registry_isolation() -> None:
    registry = json.loads(read("harness/api/printer-mapping-use-case-registry.json"))
    cases = {item["id"]: item for item in registry["use_cases"]}
    local = cases["agilant-hq.local-tcp-printer"]
    assert local["organization_id"] == "agilant"
    assert local["site_id"] == "hq"
    assert local["scope_type"] == "site_override"
    assert local["parent_use_case_id"] is None
    assert local["product_launcher"] == "Map-AgilantHqPrinter.cmd"
    assert local["product_engine"] == "mapping/Invoke-LocalTcpPrinter.ps1"
    assert local["evidence_policy"] == "harness/api/agilant-hq-local-tcp-printer-evidence-policy.json"
    assert cases["northwell.shared-printer.organization-default"]["assumptions"]["direct_ip_mapping"] is False
    assert cases["health-and-hospitals.shared-printer.discovery"]["status"] == "discovery_required"


def check_resolution_fail_closed() -> None:
    source = read("mapping/Invoke-LocalTcpPrinter.ps1")
    policy = json.loads(read("harness/api/agilant-hq-local-tcp-printer-evidence-policy.json"))
    for required in (
        "DNS_UNRESOLVED", "DNS_PANEL_MISMATCH", "AMBIGUOUS_DNS",
        "SSID_MISMATCH", "TcpSourceAddress", "Get-CurrentWifiSsid",
        "OPERATOR_PANEL_OVERRIDE", "PANEL_CONFIRMATION_REQUIRED",
        "SITE_CONFIRMATION_REQUIRED", "Test-Tcp9100",
        "DRIVER_NOT_INSTALLED", "PORT_NAME_CONFLICT",
        "UNMANAGED_QUEUE_CONFLICT", "ADOPTION_CONFIRMATION_REQUIRED",
        "ROLLBACK_INCOMPLETE", "MAPPING_FAILED_ROLLED_BACK",
        "Set-Printer", "Add-PrinterPort", "Add-Printer",
        "Get-Printer", "TEST_PAGE_SUBMITTED", "MAPPED_NOW",
        "ALREADY_MAPPED", "READY_TO_ADOPT", "READY_TO_ADOPT_STALE",
    ):
        assert required in source, required
    assert "PanelAddress" in source and "$PanelConfirmed" in source
    assert "$SiteConfirmed" in source and "$AdoptExistingQueue" in source
    assert "function Test-Tcp9100([string]$Address) {" in source
    assert "SAS_LOCAL_TCP_" in source
    assert "northwell" not in policy["use_case_id"]
    assert "physical" in policy["outcomes"]["physical_acceptance"]
    assert "re-resolve" in policy["address_change"]
    for forbidden in ("10.217.107.165", "10.217.105.164", "Plainview-Office-Printer"):
        assert forbidden not in source, "live host/IP must not be shipped as a default"


def check_gui_requires_current_observation() -> None:
    gui = read("GUI/Start-LocalTcpPrinterGui.ps1")
    for required in (
        "Map-AgilantHqPrinter.cmd", "Preview & preflight",
        "Map / Repair", "Send test page", "UsePanelAddress",
        "PanelConfirmed", "SiteConfirmed", "AdoptExistingQueue",
        "$txtPanel.Text = ''", "$chkPanel.Checked = $false",
        "Save / Update profile", "Get-PrinterDriver", "Invoke-Engine",
    ):
        assert required in gui, required
    assert "Reset-Plan" in gui
    assert "Join-Path $env:LOCALAPPDATA" in gui
    assert "observed" in read("START-HERE-AGILANT-HQ-PRINTER-MAPPING.md").lower()


def check_field_distribution() -> None:
    launcher = read("Map-AgilantHqPrinter.cmd")
    release = read("tools/build/New-DashboardFieldRelease.ps1")
    assert "Start-LocalTcpPrinterGui.ps1" in launcher
    assert "Start-Process" in launcher and "-Verb RunAs" in launcher
    for required in (
        "Map-AgilantHqPrinter.cmd",
        "GUI\\Start-LocalTcpPrinterGui.ps1",
        "mapping\\Invoke-LocalTcpPrinter.ps1",
    ):
        assert required in release, required
    assert not (ROOT / "Map-LocalTcpPrinter.cmd").exists(), "generic entrypoint would cross site boundaries"


def main() -> None:
    checks = (
        check_registry_isolation, check_resolution_fail_closed,
        check_gui_requires_current_observation, check_field_distribution,
    )
    for check in checks:
        check()
        print("PASS:", check.__name__)
    print(f"PASS: {len(checks)} Agilant HQ printer contract groups; no live printer contacted")


if __name__ == "__main__":
    main()
