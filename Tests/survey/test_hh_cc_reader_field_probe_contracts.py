#!/usr/bin/env python3
"""Contracts for the H&H CC-reader read-only field probe."""
from __future__ import annotations

import json
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
    registry = json.loads(read("harness/api/harness-command-registry.json"))

    for marker in (
        "Invoke-SasNetworkAwareField.ps1\" refresh",
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

    private_markers = (
        "10.217.101.192",
        "C8:40:52:3C:54:B6",
        "2942",
    )
    joined = "\n".join((launcher, script, docs))
    for marker in private_markers:
        assert marker not in joined, f"live/private H&H value leaked into tracked field probe: {marker}"

    assert "private H&H Google Drive technician instructions remain authoritative" in docs
    assert "1D Code 128" in docs
    assert "reusable barcode generator is explicitly deferred" in docs

    entries = {entry["id"]: entry for entry in registry["commands"]}
    assert "hh-cc-reader-probe" in entries, "command registry missing hh-cc-reader-probe"
    entry = entries["hh-cc-reader-probe"]
    assert entry["source_of_truth"] == "Probe-HHCCReader.cmd"
    assert entry["mutation"] == "local_runtime"
    assert entry["network"] is True

    print("[PASS] H&H CC-reader workflow has a tracked CMD front door")
    print("[PASS] Probe is one-target, network-gated, optional-MAC-gated, and read-only")
    print("[PASS] Live H&H IP/MAC/credential values are excluded from tracked artifacts")
    print("[PASS] Drive remains field authority and barcode-generator work is deferred")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
