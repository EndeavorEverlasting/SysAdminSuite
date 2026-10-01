#!/usr/bin/env python3
"""Contracts for the H&H CC-reader network-switch and authorized home-lab workflow."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    p = ROOT / path
    assert p.is_file(), f"missing required file: {path}"
    return p.read_text(encoding="utf-8-sig")


def main() -> int:
    prepare = read("Prepare-HHCCReaderNetworkSwitch.cmd")
    checkpoint_cmd = read("Checkpoint-HHCCReaderNetwork.cmd")
    checkpoint_ps = read("scripts/Invoke-SasHhCcReaderNetworkCheckpoint.ps1")
    discover_cmd = read("Discover-HHCCReaderHomeLab.cmd")
    discover_ps = read("scripts/Invoke-SasHhCcReaderHomeLabDiscovery.ps1")
    alpha_cmd = read("Plan-HHCCReaderAlphaInput.cmd")
    alpha_ps = read("scripts/ConvertTo-SasPaxKeypadPlan.ps1")
    docs = read("docs/HH_CC_READER_HOME_LAB_WORKFLOW.md")
    registry = json.loads(read("harness/api/harness-command-registry.json"))
    outcomes = json.loads(read("harness/api/harness-outcome-registry.json"))
    artifacts = json.loads(read("harness/api/harness-artifact-registry.json"))

    for marker in (
        'Invoke-SasNetworkAwareField.ps1" refresh',
        "C:\\SASAL\\Checkpoint-HHCCReaderNetwork.cmd",
        "C:\\SASAL\\Discover-HHCCReaderHomeLab.cmd",
    ):
        assert marker in prepare, f"prepare launcher missing marker: {marker}"

    for marker in (
        "Invoke-SasHhCcReaderNetworkCheckpoint.ps1",
        "BEFORE_SWITCH",
        "AFTER_SWITCH",
    ):
        assert marker in checkpoint_cmd + checkpoint_ps, f"checkpoint missing marker: {marker}"

    for marker in (
        "AUTHORIZED_CONSUMER_LAB",
        "Get-NetRoute",
        "Get-NetNeighbor",
        "System.Net.NetworkInformation.Ping",
        "MaxHosts = 512",
        "HOME_LAB_SCOPE_TOO_LARGE",
        "same_oui_candidates",
        "Invoke-SasHhCcReaderProbe.ps1",
        "BOUNDED_LOCAL_DISCOVERY_EXACT_MAC",
    ):
        assert marker in discover_cmd + discover_ps, f"home-lab discovery missing marker: {marker}"

    forbidden_discovery = (
        "nmap ",
        "naabu ",
        "masscan ",
        "adb ",
        "fastboot ",
        "Set-NetIPAddress",
        "New-NetIPAddress",
        "Remove-NetIPAddress",
        "Set-DnsClient",
        "Invoke-Command",
        "Enter-PSSession",
    )
    lowered = discover_ps.lower()
    for marker in forbidden_discovery:
        assert marker.lower() not in lowered, f"home-lab discovery contains forbidden marker: {marker}"

    for marker in (
        "press the number key containing the letter",
        "ALPHA until",
        "SPECIAL_CHARACTER_UNPROVEN",
    ):
        assert marker.lower() in (alpha_cmd + alpha_ps + docs).lower(), f"alpha plan missing marker: {marker}"

    tracked = "\n".join((prepare, checkpoint_cmd, checkpoint_ps, discover_cmd, discover_ps, alpha_cmd, alpha_ps, docs))
    secret_literals = (
        "pax" + "9876" + "@@",
        "29" + "42",
    )
    for secret_literal in secret_literals:
        assert secret_literal.lower() not in tracked.lower(), f"tracked home-lab workflow embeds credential literal: {secret_literal}"

    live_literals = (
        ".".join(("192", "168", "1", "89")),
        "-".join(("C8", "40", "52", "3C", "93", "BA")),
        "".join(("124", "047", "3751")),
    )
    for live_literal in live_literals:
        assert live_literal not in tracked, f"tracked home-lab workflow embeds live field value: {live_literal}"

    entries = {entry["id"]: entry for entry in registry["commands"]}
    expected_commands = {
        "hh-cc-reader-network-switch-prepare": ("Prepare-HHCCReaderNetworkSwitch.cmd RUN_ID [EXPECTED_MAC]", True),
        "hh-cc-reader-network-checkpoint": ("Checkpoint-HHCCReaderNetwork.cmd PHASE RUN_ID [EXPECTED_MAC] [LABEL]", False),
        "hh-cc-reader-home-lab-discovery": ("Discover-HHCCReaderHomeLab.cmd RUN_ID [EXPECTED_MAC]", True),
        "hh-cc-reader-alpha-input-plan": ("Plan-HHCCReaderAlphaInput.cmd TEXT", False),
    }
    for command_id, (command, network) in expected_commands.items():
        assert command_id in entries, f"command registry missing {command_id}"
        assert entries[command_id]["command"] == command
        assert entries[command_id]["network"] is network

    contracts = {entry["command_id"]: entry for entry in outcomes["contracts"]}
    for command_id in expected_commands:
        assert command_id in contracts, f"outcome registry missing {command_id}"

    artifact_ids = {entry["id"] for entry in artifacts["artifacts"]}
    assert "hh-cc-reader-network-checkpoint-result" in artifact_ids
    assert "hh-cc-reader-home-lab-discovery-result" in artifact_ids

    assert "PROTECTED_ENTERPRISE" in docs
    assert "AUTHORIZED_CONSUMER_LAB" in docs
    assert "does **not** weaken" in docs
    assert "merchanthelp.bankofamerica.com/Pax-Terminal-Configuration" in docs

    print("[PASS] H&H network-switch checkpoint is a tracked CMD workflow")
    print("[PASS] Authorized consumer-lab discovery is bounded and exact-MAC gated")
    print("[PASS] PAX-family alpha-input planning is codified without tracked credentials")
    print("[PASS] Home-lab workflow registers commands, outcomes, and ignored evidence")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
