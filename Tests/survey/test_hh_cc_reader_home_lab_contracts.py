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
        "CONFIRM_CONSUMER_LAB",
        "SEALED_RUNTIME_REQUIRED",
        "HOME_LAB_NETWORK_AUTHORITY_REJECTED",
        "prepared_commit_verified",
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

    # Launcher-gate regression (2026-10-01): a left-side `>nul 2>&1` redirect
    # sends the echoed gate value to nul instead of the pipe, so findstr always
    # fails and every valid RUN_ID/MAC wrongly falls through to :usage. Silence
    # belongs on the findstr side of the pipe.
    for name, text in (
        ("Prepare-HHCCReaderNetworkSwitch.cmd", prepare),
        ("Checkpoint-HHCCReaderNetwork.cmd", checkpoint_cmd),
        ("Discover-HHCCReaderHomeLab.cmd", discover_cmd),
    ):
        assert ">nul 2>&1 echo(" not in text, f"{name} pipes gate input into nul"
        assert 'findstr.exe" /R /X "[' in text, f"{name} missing findstr gate"
        assert "if errorlevel 1 goto usage" in text, f"{name} missing gate fallthrough"

    # Console-title regression (2026-10-01): unescaped `&` in `title ... H&H ...`
    # terminates the command so cmd tries to run `H ...` as a program.
    for name, text in (
        ("Prepare-HHCCReaderNetworkSwitch.cmd", prepare),
        ("Checkpoint-HHCCReaderNetwork.cmd", checkpoint_cmd),
        ("Discover-HHCCReaderHomeLab.cmd", discover_cmd),
        ("Plan-HHCCReaderAlphaInput.cmd", alpha_cmd),
    ):
        assert "title SysAdminSuite - H^&H" in text, f"{name} title must escape H&&H"
        assert "title SysAdminSuite - H&H" not in text, f"{name} title leaves & unescaped"

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
        "hh-cc-reader-network-checkpoint": ("Checkpoint-HHCCReaderNetwork.cmd PHASE RUN_ID [EXPECTED_MAC]", False),
        "hh-cc-reader-home-lab-discovery": ("Discover-HHCCReaderHomeLab.cmd RUN_ID CONFIRM_CONSUMER_LAB [EXPECTED_MAC]", True),
        "hh-cc-reader-alpha-input-plan": ("Plan-HHCCReaderAlphaInput.cmd", False),
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
    assert "hh-cc-reader-alpha-input-plan-result" in artifact_ids
    assert "home-lab-state-{0}.json" in checkpoint_ps
    assert "NETWORK_CHECKPOINT_NO_ACTIVE_IPV4" in checkpoint_ps
    assert "before_checkpoint" in checkpoint_ps

    # Null-NetProfile regression (2026-10-01): strict mode throws on
    # `$config.NetProfile.Name` when an active adapter (for example WSL
    # vEthernet) exposes a null profile, aborting the whole capture.
    assert "if ($null -ne $config.NetProfile)" in checkpoint_ps, (
        "checkpoint must guard null NetProfile before reading .Name"
    )
    assert "[string]$config.NetProfile.Name`n" not in checkpoint_ps, (
        "checkpoint reads NetProfile.Name without a null guard"
    )
    # Null-pipe regression (2026-10-01): `$null | ForEach-Object` still runs the
    # block once with $_ = $null, so strict mode aborts on $_.NextHop for
    # adapters without a default gateway (for example WSL vEthernet).
    assert "$config.IPv4DefaultGateway | Where-Object { $null -ne $_ } |" in checkpoint_ps, (
        "checkpoint must filter null gateway entries before reading .NextHop"
    )
    # Missing-property regression (2026-10-01): some hosts expose route rows
    # without a PolicyStore property, so strict mode must feature-detect it.
    assert "PSObject.Properties['PolicyStore']" in checkpoint_ps, (
        "checkpoint must feature-detect PolicyStore before reading it"
    )

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
