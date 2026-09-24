#!/usr/bin/env python3
"""Contracts for the H&H CC-reader read-only field probe."""
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
    launcher = read("Probe-HHCCReader.cmd")
    script = read("scripts/Invoke-SasHhCcReaderProbe.ps1")
    docs = read("docs/HH_CC_READER_FIELD_PROBE.md")
    external_evidence = read("docs/EXTERNAL_FIELD_EVIDENCE.md")
    registry = json.loads(read("harness/api/harness-command-registry.json"))

    for marker in (
        'Invoke-SasNetworkAwareField.ps1" refresh',
        "C:\\SASAL\\Probe-HHCCReader.cmd",
        "Invoke-SasHhCcReaderProbe.ps1",
        "Probe-HHCCReader.cmd IPV4 [EXPECTED-MAC]",
    ):
        assert marker in launcher, f"launcher missing marker: {marker}"

    for marker in (
        "Get-NetIPConfiguration",
        "Test-SasSameIPv4Subnet",
        "Get-NetNeighbor",
        "Test-Connection",
        "Test-NetConnection",
        "NETWORK_MISMATCH",
        "NETWORK_AMBIGUOUS",
        "DEVICE_MISMATCH",
        "DEVICE_UNRESOLVED",
        "READ_ONLY_PROBE_COMPLETE",
        "survey\\output\\hh-cc-reader",
    ):
        assert marker in script, f"probe missing marker: {marker}"

    forbidden_mutation = (
        "Set-NetIPAddress",
        "New-NetIPAddress",
        "Remove-NetIPAddress",
        "Set-DnsClient",
        "Restart-Computer",
        "Invoke-Command",
        "Enter-PSSession",
        "adb ",
        "fastboot ",
    )
    lowered = script.lower()
    for marker in forbidden_mutation:
        assert marker.lower() not in lowered, f"read-only probe contains forbidden mutation marker: {marker}"

    joined = "\n".join((launcher, script, docs))
    ipv4_literals = set(re.findall(r"(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?!\d)", joined))
    documentation_network = ipaddress.ip_network("192.0.2.0/24")
    for literal in ipv4_literals:
        address = ipaddress.ip_address(literal)
        assert address in documentation_network, (
            f"tracked field probe contains non-TEST-NET IPv4 literal: {literal}"
        )

    mac_literals = set(
        re.findall(r"(?i)\b(?:[0-9a-f]{2}[-:]){5}[0-9a-f]{2}\b", joined)
    )
    assert mac_literals <= {"AA-BB-CC-DD-EE-FF"}, (
        f"tracked field probe contains non-synthetic MAC literal(s): {sorted(mac_literals)}"
    )

    assert "operator-managed external technician instructions remain authoritative" in docs
    assert "EXTERNAL_FIELD_EVIDENCE.md" in docs
    assert "runtime dependencies" in docs
    assert "1D Code 128" in docs
    assert "reusable barcode generator is explicitly deferred" in docs

    provider_neutral = "\n".join((docs, external_evidence))
    for provider_marker in ("Google Drive", "drive.google.com", "OneDrive", "Dropbox"):
        assert provider_marker not in provider_neutral, (
            f"provider-specific external evidence leaked into tracked field docs: {provider_marker}"
        )
    for marker in (
        "not a repository dependency",
        "must not require, discover, authenticate to, crawl, mount, synchronize",
        "external evidence is available",
        "personal cloud-account identifiers",
    ):
        assert marker in external_evidence, f"external evidence boundary missing marker: {marker}"

    entries = {entry["id"]: entry for entry in registry["commands"]}
    assert "hh-cc-reader-probe" in entries, "command registry missing hh-cc-reader-probe"
    entry = entries["hh-cc-reader-probe"]
    assert entry["source_of_truth"] == "Probe-HHCCReader.cmd"
    assert entry["mutation"] == "local_runtime"
    assert entry["network"] is True

    print("[PASS] H&H CC-reader workflow has a tracked CMD front door")
    print("[PASS] Probe is one-target, network-gated, optional-MAC-gated, and read-only")
    print("[PASS] Tracked artifacts contain only TEST-NET IPv4 and synthetic MAC examples")
    print("[PASS] External field evidence is provider-neutral and barcode-generator work is deferred")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
