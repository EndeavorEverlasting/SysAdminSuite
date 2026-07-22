#!/usr/bin/env python3
"""Dependency-free contracts for the clickable Cybernet live-cert surface."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADVANCED_LAUNCHER = ROOT / "Run-CybernetClientConfiguration.cmd"
LIVE_LAUNCHER = ROOT / "Run-CybernetLiveCert.cmd"
PILOT = ROOT / "Hardware/Cybernet/Invoke-CybernetClientPilot.ps1"
RESOLVER = ROOT / "scripts/SasTargetNameResolution.psm1"
PROFILE = ROOT / "Config/cybernet-client-preferences.json"
GUIDE = ROOT / "docs/tutorials/CYBERNET_CLIENT_PILOT.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def test_clickable_cmd_owns_technician_input_and_results() -> None:
    launcher = read(LIVE_LAUNCHER)
    for marker in (
        'set /p "TARGET=Cybernet hostname: "',
        "Use the short hostname",
        "resolves and proves the FQDN automatically",
        "Invoke-CybernetClientPilot.ps1",
        "-OpenResults",
        "Any unresolved, ambiguous, or failed gate stops",
        "pause",
    ):
        assert marker in launcher
    assert "domain.example" not in launcher
    assert "-ExecutionPolicy Bypass" not in launcher


def test_advanced_launcher_routes_pilot_to_the_same_surface() -> None:
    launcher = read(ADVANCED_LAUNCHER)
    for marker in (
        'if /I "%MODE%"=="Pilot" goto pilot',
        "Run-CybernetLiveCert.cmd",
        "resolves one canonical FQDN automatically",
        "Invoke-CybernetClientPilot.ps1",
        "-OpenResults",
        "PILOT_COMPLETE_TECHNICIAN_ACCEPTANCE_REQUIRED",
    ):
        assert marker in launcher


def test_pilot_orders_resolution_and_proof_before_production() -> None:
    pilot = read(PILOT)
    ordered_markers = (
        "Assert-SasNorthwellWifi",
        "Resolve-SasCanonicalTargetFqdn -TargetName $ComputerName",
        "Invoke-SasPilotConfigurationMode -Mode Plan",
        "Invoke-SasPilotPowerShellStage -Name 'transport-preflight'",
        "Invoke-SasPilotPowerShellStage -Name 'transport-live-cert'",
        "[string]$liveCert.disposition -ne 'LIVE CERT PASS'",
        "$PSCmdlet.ShouldProcess",
        "Invoke-SasPilotConfigurationMode -Mode Apply",
        "Invoke-SasPilotConfigurationMode -Mode Validate",
    )
    positions = [pilot.index(marker) for marker in ordered_markers]
    assert positions == sorted(positions)


def test_pilot_uses_resolved_fqdn_and_emits_openable_handoff() -> None:
    pilot = read(PILOT)
    for marker in (
        "$resolvedFqdn = [string]$resolution.fqdn",
        "-ComputerName $resolvedFqdn",
        "OPEN-ME-CYBERNET-LIVE-CERT.txt",
        "cybernet_live_cert_summary.json",
        "Start-Process -FilePath 'notepad.exe'",
        "Start-Process -FilePath 'explorer.exe'",
        "ACTION_REQUIRED",
        "LIVE_CERT_PASS_PRODUCTION_NOT_RUN",
        "PILOT_COMPLETE_TECHNICIAN_ACCEPTANCE_REQUIRED",
        "autologon_position = 'last'",
        "automatic_reboot_performed = $false",
    ):
        assert marker in pilot
    for forbidden in (
        "Get-Credential",
        "Restart-Computer",
        "shutdown.exe",
        "Invoke-CybernetComPortAutoFix.ps1",
        "-ExecutionPolicy Bypass",
    ):
        assert forbidden not in pilot


def test_resolver_fails_closed_without_tracked_internal_suffix() -> None:
    resolver = read(RESOLVER)
    for marker in (
        "Get-DnsClientGlobalSetting",
        "Get-DnsClient",
        "USERDNSDOMAIN",
        "SAS_TARGET_DNS_SUFFIXES",
        "Resolve-SasCanonicalTargetFqdn",
        "multiple canonical FQDNs",
        "different canonical host identity",
        "do not guess or append a domain manually",
        "UNIQUE_CANONICAL_FQDN",
    ):
        assert marker in resolver
    assert "northwell.edu" not in resolver.lower()


def test_profile_codifies_target_identity_resolution() -> None:
    profile = json.loads(read(PROFILE))
    identity = profile["target_identity"]
    assert identity["operator_input"] == "short_hostname_or_fqdn"
    assert identity["canonical_transport_identity"] == "unique_dns_fqdn"
    assert identity["unresolved_policy"] == "fail_closed"
    assert identity["ambiguous_policy"] == "fail_closed"
    assert identity["canonical_name_mismatch_policy"] == "fail_closed"
    assert identity["manual_domain_append_forbidden"] is True
    assert identity["tracked_internal_dns_suffix_forbidden"] is True


def test_technician_guide_requires_only_click_and_short_hostname() -> None:
    guide = read(GUIDE)
    for marker in (
        "Double-click `Run-CybernetLiveCert.cmd`",
        "authorized short Cybernet hostname",
        "Do not derive, append, or type a DNS domain",
        "root live-cert CMD owns the technician sequence",
        "Canonical name gate",
        "Deployment dry run",
        "Harmless live certification",
        "AutoLogon must remain last",
        "OPEN-ME-CYBERNET-LIVE-CERT.txt",
        "PILOT_COMPLETE_TECHNICIAN_ACCEPTANCE_REQUIRED",
    ):
        assert marker in guide


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: Cybernet clickable live-cert contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
