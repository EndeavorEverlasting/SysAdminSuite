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
    netstat_docs = read("docs/HH_CC_READER_NETSTAT_BASELINE.md")
    external_evidence = read("docs/EXTERNAL_FIELD_EVIDENCE.md")
    registry = json.loads(read("harness/api/harness-command-registry.json"))

    for marker in (
        'Invoke-SasNetworkAwareField.ps1" refresh',
        "C:\\SASAL\\Probe-HHCCReader.cmd",
        "Invoke-SasHhCcReaderProbe.ps1",
        "Probe-HHCCReader.cmd IPV4 [EXPECTED-MAC]",
    ):
        assert marker in launcher, f"launcher missing marker: {marker}"

    # Console-title regression (2026-10-01): unescaped `&` in the title line
    # splits the command so cmd tries to run `H ...` as a program.
    assert "title SysAdminSuite - H^&H" in launcher, "probe title must escape H&&H"
    assert "title SysAdminSuite - H&H" not in launcher, "probe title leaves & unescaped"

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

    # Field regression: some active adapters (for example WSL vEthernet) can expose
    # a null NetProfile under strict mode, and Windows PowerShell 5.1 can reject
    # @($genericList) with "Argument types do not match".
    assert "if ($null -ne $config.NetProfile)" in script
    assert "Network = $networkName" in script
    assert "$networkRows = $rows.ToArray()" in script
    assert "$result.network = $networkRows" in script
    assert "$result.network = @($rows)" not in script

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

    joined = "\n".join((launcher, script, docs, netstat_docs))
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
    assert "HH_CC_READER_NETSTAT_BASELINE.md" in docs
    assert "PAX Store Push Service Primary (443)" in docs
    assert "EXTERNAL_FIELD_EVIDENCE.md" in docs
    assert "runtime dependencies" in docs
    assert "1D Code 128" in docs
    assert "reusable barcode generator is explicitly deferred" in docs

    for marker in (
        "Active Internet connections (w/o servers)",
        "PAX Store Push Service Primary (443)",
        "scripts/Invoke-SasHhCcReaderProbe.ps1",
        "four linked baselines",
        "Firmware configuration gate",
        "Probe-HHCCReaderEndpoint.cmd",
        "Passive workstation-capture topology caveat",
        "quiet `pktmon` window",
        "Issue #436 remains the field-acceptance ledger",
        "Evidence linkage contract",
        "RUN_ID",
        "exactly one reader identity",
        "workstation probe receipt **path and receipt timestamp**",
        # Two-axis provenance semantics: artifact provenance and discriminator
        # satisfaction are separate fields, and a prior-run artifact may satisfy
        # a current discriminator without a same-run duplicate.
        "Prior-provenance satisfaction and no-restage rule",
        "ARTIFACT_PROVENANCE",
        "DISCRIMINATOR_STATE",
        "SATISFIED_BY_PRIOR_PROVENANCE",
        "RESTAGE_REQUIRED=NO",
        "REMOTE_ENDPOINT_CANDIDATE=NONE",
        "cannot be relabeled",
        "recorded invalidation reason",
        "never forces a repeat",
        "advance to the next unresolved discriminator",
        "Same-window proof stays strict",
        "harness/api/evidence-provenance-registry.json",
        # Management-plane P5 ledger: typed access dispositions and the
        # estate-authority gate for exact package 2.0.15.260522.
        "Management-plane candidate disposition (2026-10-01)",
        "ACCESS_NOT_PROVEN",
        "PROVEN_ACCESS",
        "BLOCKED_AUTHORITY",
        "Strongest next mechanism gate",
        "2.0.15.260522",
        "Do not restage another reader window for this gap",
        "Estate-authority evidence packet",
        "Experian",
        "Strongest documented owner-contact candidate",
        "Public H&H merchant-services ownership evidence",
        "Gordon source-level update-feasibility evidence (2026-09-28)",
        "two or three credit-card readers at home",
        "Remote-update feasibility is source-level supported",
        "not authorization",
        "Mechanism-first firmware update discovery (P13 recurrence fix)",
        "mechanism exhaustion",
        "CREDENTIAL_GATE",
        "Human escalation",
        "AUTHORITY_PACKET_ID",
        "PACKAGE_EXPOSED_FOR_2_0_15_260522",
        "ASSIGNMENT_METHOD",
        "ROLLBACK_EXCEPTION_PATH",
        "POST_UPDATE_ACCEPTANCE",
        "management-baseline closure review",
    ):
        assert marker in netstat_docs, f"Netstat baseline contract missing marker: {marker}"

    phase_section = netstat_docs.split("## Canonical Netstat evidence phases", 1)[1].split(
        "## Workstation correlation lane", 1
    )[0]
    phase_order = re.findall(
        r"(?m)^(\d+)\. \*\*(Identity gate|BASELINE|START_TEST|DURING_TEST|POST_TEST)\*\*",
        phase_section,
    )
    assert phase_order == [
        ("1", "Identity gate"),
        ("2", "BASELINE"),
        ("3", "START_TEST"),
        ("4", "DURING_TEST"),
        ("5", "POST_TEST"),
    ], f"Netstat phase numbering/order changed or duplicated: {phase_order}"
    assert "before pressing Netstat `START TEST`" in phase_section
    assert "immediately after the controlled action" in phase_section

    provider_neutral = "\n".join((docs, netstat_docs, external_evidence))
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
    print("[PASS] Netstat baseline and capture-topology semantics remain read-only and provider-neutral")
    print("[PASS] External field evidence is provider-neutral and barcode-generator work is deferred")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
