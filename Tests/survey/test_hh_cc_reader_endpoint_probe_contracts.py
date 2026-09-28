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
    command_registry = json.loads(read("harness/api/harness-command-registry.json"))
    artifact_registry = json.loads(read("harness/api/harness-artifact-registry.json"))
    outcome_registry = json.loads(read("harness/api/harness-outcome-registry.json"))

    for marker in (
        'Invoke-SasNetworkAwareField.ps1" refresh',
        "C:\\SASAL\\Probe-HHCCReaderEndpoint.cmd",
        "Probe-HHCCReader.cmd",
        "Invoke-SasHhCcReaderEndpointProbe.ps1",
        "READER_IPV4 REMOTE_ENDPOINT [PORT] [EXPECTED-MAC]",
    ):
        assert marker in launcher, f"endpoint launcher missing marker: {marker}"

    for marker in (
        "CheckHostName",
        "Test-NetConnection",
        "REMOTE_ENDPOINT_CORRELATION_COMPLETE",
        "REMOTE_ENDPOINT_TEST_ERROR",
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

    assert "CIDRs, ranges, wildcards" in launcher
    assert "CIDRs, ranges, wildcards" in script
    assert "one observed-and-approved REMOTE_ENDPOINT + one PORT" in docs
    assert "CC-reader software/firmware deployment" in docs
    assert "remains blocked" in docs

    joined = "\n".join((launcher, script, docs))
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
    assert command["mutation"] == "local_runtime"
    assert command["network"] is True

    artifacts = {entry["id"]: entry for entry in artifact_registry["artifacts"]}
    assert "hh-cc-reader-endpoint-probe-result" in artifacts
    assert artifacts["hh-cc-reader-endpoint-probe-result"]["tracked"] is False
    assert artifacts["hh-cc-reader-endpoint-probe-result"]["contains_live_data"] is True

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
