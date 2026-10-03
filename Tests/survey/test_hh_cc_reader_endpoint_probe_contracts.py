#!/usr/bin/env python3
"""Contracts for the bounded H&H CC-reader endpoint-correlation probe."""
from __future__ import annotations

import ipaddress
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    p = ROOT / path
    assert p.is_file(), f"missing required file: {path}"
    return p.read_text(encoding="utf-8-sig")


def main() -> int:
    launcher = read("Probe-HHCCReaderEndpoint.cmd")
    script = read("scripts/Invoke-SasHhCcReaderEndpointProbe.ps1")
    docs = read("docs/HH_CC_READER_REMOTE_OPERATIONS_PROGRAM.md")
    qr_plan = read("docs/HH_CC_READER_QR_BASELINE_PLAN.md")
    command_registry = json.loads(read("harness/api/harness-command-registry.json"))
    artifact_registry = json.loads(read("harness/api/harness-artifact-registry.json"))
    outcome_registry = json.loads(read("harness/api/harness-outcome-registry.json"))
    firmware_policy = json.loads(read("harness/api/hh-cc-reader-firmware-policy.json"))

    for marker in (
        'Invoke-SasNetworkAwareField.ps1" refresh',
        "C:\\SASAL\\Probe-HHCCReaderEndpoint.cmd",
        "Probe-HHCCReader.cmd",
        "Invoke-SasHhCcReaderEndpointProbe.ps1",
        "READER_IPV4 REMOTE_ENDPOINT PORT APPROVAL_REF [EXPECTED-MAC] [NETWORK-ENVIRONMENT]",
        "HOSPITAL_GUEST_SHARED",
    ):
        assert marker in launcher, f"endpoint launcher missing marker: {marker}"

    # Console-title regression (2026-10-01): unescaped `&` in the title line
    # splits the command so cmd tries to run `H ...` as a program.
    assert "title SysAdminSuite - H^&H" in launcher, "endpoint title must escape H&&H"
    assert "title SysAdminSuite - H&H" not in launcher, "endpoint title leaves & unescaped"

    for marker in (
        "CheckHostName",
        "Test-NetConnection",
        "REMOTE_ENDPOINT_CORRELATION_COMPLETE",
        "REMOTE_ENDPOINT_TEST_ERROR",
        "ApprovalRef",
        "approval_reference_supplied = $true",
        "ValidateOnly",
        "ENDPOINT_INPUT_VALID",
        "NetworkEnvironment",
        "network_environment_classified",
        "[Guid]::NewGuid()",
        "yyyyMMdd-HHmmss-fff",
        "survey\\output\\hh-cc-reader",
        "ownership_proven = $false",
    ):
        assert marker in script, f"endpoint probe missing marker: {marker}"

    forbidden = (
        "Set-NetIPAddress",
        "New-NetIPAddress",
        "Remove-NetIPAddress",
        "Set-DnsClient",
        "Restart-Computer",
        "Invoke-Command",
        "Enter-PSSession",
        "Get-NetTCPConnection",
        "nmap",
        "naabu",
        "adb ",
        "fastboot ",
    )
    lowered = script.lower()
    for marker in forbidden:
        assert marker.lower() not in lowered, f"endpoint probe contains forbidden marker: {marker}"

    # Shell metacharacters must remain inside quoted positional expansions until
    # the PowerShell validator applies the stricter endpoint/reference grammar.
    assert 'call "C:\\SASAL\\Probe-HHCCReaderEndpoint.cmd" "%~1" "%~2" "%~3" "%~4" "%~5" "%~6"' in launcher
    assert '-ReaderIPAddress "%~1" -RemoteEndpoint "%~2" -RemotePort "%~3" -ApprovalRef "%~4" -NetworkEnvironment "%NETWORK_ENVIRONMENT%" -ValidateOnly' in launcher
    assert 'call "%~dp0Probe-HHCCReader.cmd" "%~1" "%~5" "%~6"' in launcher
    launcher_lines = {line.strip() for line in launcher.splitlines()}
    assert 'call "%~dp0Probe-HHCCReader.cmd" "%~1" "%~5"' not in launcher_lines
    assert 'if "%~6"=="" goto usage' in launcher
    assert 'Probe-HHCCReaderEndpoint.cmd" %*' not in launcher
    assert "-ReaderIPAddress %1" not in launcher
    assert "-RemoteEndpoint %2" not in launcher
    assert "-ApprovalRef %4" not in launcher

    normalized_launcher = re.sub(r"\s+", " ", launcher)
    assert "CIDRs, ranges, wildcards" in normalized_launcher
    assert "CIDRs, ranges, wildcards" in script
    assert "ApprovalRef must be a non-secret" in script
    assert "network_environment = $NetworkEnvironment" in script
    assert "one observed REMOTE_ENDPOINT + one explicit PORT + one APPROVAL_REF" in docs
    assert "cannot independently validate the external human approval source" in docs
    assert "CC-reader software/firmware deployment" in docs
    assert "remains blocked" in docs
    assert "mechanism discovery is now governed by" in docs
    assert "management owner is an output, not a prerequisite supplied by a client or coworker" in docs
    assert "Payment Fusion Control Center / Healthcare Omni-Channel" in docs
    assert "PAXSTORE OTA firmware push" in docs
    assert "`CREDENTIAL_GATE`" in docs
    assert "`NOT_APPLICABLE`" in docs
    assert "owner-identification requests" in docs
    p5 = docs.split("### P5 — management-plane discovery", 1)[1].split("### P6 — one-reader deployment pilot", 1)[0]
    mechanism = {item["id"]: item for item in firmware_policy["mechanism_discovery"]["candidate_order"]}
    state_markers = {
        "payment-fusion-control-center": "Payment Fusion Control Center / Healthcare Omni-Channel",
        "paxstore-ota-push": "PAXSTORE OTA firmware push",
        "provider-auto-update": "provider-managed automatic update",
    }
    for candidate_id, marker in state_markers.items():
        line = next((line for line in p5.splitlines() if marker in line), "")
        assert line, f"P5 program lost mechanism marker: {marker}"
        assert f"`{mechanism[candidate_id]['disposition']}`" in line, (
            f"P5 program drifted from firmware policy for {candidate_id}: {line}"
        )
    assert mechanism["terminal-tms-pull"]["disposition"] == "NOT_APPLICABLE"
    assert "`NOT_APPLICABLE`" in p5
    assert "strongest next gate is confirmation from the current H&H Experian" not in docs
    assert "current H&H owner of the Experian merchant-services/terminal relationship" not in docs
    assert "Probe-HHCCReaderEndpoint.cmd READER_IPV4 REMOTE_ENDPOINT PORT APPROVAL_REF [EXPECTED-MAC] [NETWORK-ENVIRONMENT]" in qr_plan
    assert "QR-eligible but not yet scanner-ready" in qr_plan
    assert "Raw `Test-NetConnection` snippets are component diagnostics only" in qr_plan
    assert "blocked until endpoint CMD exists" not in qr_plan
    assert "Probe-HHCCReaderEndpoint.cmd APPROVED_REMOTE_HOST_OR_IP [PORT]" not in qr_plan
    assert "Google Drive" not in qr_plan

    joined = "\n".join((launcher, script, docs, qr_plan))
    ipv4_literals = set(re.findall(r"(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?!\d)", joined))
    allowed_networks = (
        ipaddress.ip_network("192.0.2.0/24"),
        ipaddress.ip_network("198.51.100.0/24"),
        ipaddress.ip_network("203.0.113.0/24"),
    )
    for literal in ipv4_literals:
        address = ipaddress.ip_address(literal)
        assert any(address in network for network in allowed_networks), (
            f"tracked endpoint lane contains non-documentation IPv4 literal: {literal}"
        )

    mac_literals = set(re.findall(r"(?i)\b(?:[0-9a-f]{2}[-:]){5}[0-9a-f]{2}\b", joined))
    assert mac_literals <= {"AA-BB-CC-DD-EE-FF"}

    commands = {entry["id"]: entry for entry in command_registry["commands"]}
    assert "hh-cc-reader-endpoint-probe" in commands
    command = commands["hh-cc-reader-endpoint-probe"]
    assert command["source_of_truth"] == "Probe-HHCCReaderEndpoint.cmd"
    assert "[NETWORK_ENVIRONMENT]" in command["command"]
    assert command["mutation"] == "local_runtime"
    assert command["network"] is True

    artifacts = {entry["id"]: entry for entry in artifact_registry["artifacts"]}
    assert "hh-cc-reader-endpoint-probe-result" in artifacts
    assert artifacts["hh-cc-reader-endpoint-probe-result"]["tracked"] is False
    assert artifacts["hh-cc-reader-endpoint-probe-result"]["contains_live_data"] is True
    assert "[NETWORK_ENVIRONMENT]" in artifacts["hh-cc-reader-endpoint-probe-result"]["generator"]
    assert "<timestamp>-<8hex>.json" in artifacts["hh-cc-reader-endpoint-probe-result"]["path"]

    outcomes = {entry["command_id"]: entry for entry in outcome_registry["contracts"]}
    assert "hh-cc-reader-endpoint-probe" in outcomes
    assert outcomes["hh-cc-reader-endpoint-probe"]["success_artifact_id"] == "hh-cc-reader-endpoint-probe-result"

    print("[PASS] Endpoint correlation has a tracked CMD front door")
    print("[PASS] Canonical reader probe gates endpoint correlation first")
    print("[PASS] Endpoint lane is one-target/one-port, read-only, and no-scan")
    print("[PASS] Tracked files contain only documentation-safe example identities")
    print("[PASS] Command/artifact/outcome registries converge on the endpoint receipt")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
