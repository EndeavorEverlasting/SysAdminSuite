#!/usr/bin/env python3
"""Contracts for the H&H CC-reader network-switch and authorized home-lab workflow."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    p = ROOT / path
    assert p.is_file(), f"missing required file: {path}"
    return p.read_text(encoding="utf-8-sig")


def parse_presence_pass_contract(text: str) -> tuple[int, int, int]:
    match = re.search(
        r"\[ValidateRange\((\d+),(\d+)\)\]\s*\[int\]\$MaxPresencePasses\s*=\s*(\d+)",
        text,
    )
    assert match, "MaxPresencePasses validation/default contract is missing"
    return tuple(int(value) for value in match.groups())


def assert_presence_pass_contract(text: str) -> None:
    assert parse_presence_pass_contract(text) == (1, 2, 2), (
        "home-lab presence-pass contract must be min=1, max=2, default=2"
    )


def producer_receipt_template(text: str) -> str:
    match = re.search(
        r'Join-Path \$outputRoot \("([^"]+)" -f \$stamp,\$suffix\)',
        text,
    )
    assert match, "home-lab receipt producer format is missing"
    return match.group(1).replace("{0}", "<timestamp>").replace("{1}", "<8hex>")


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
        "-NetworkEnvironment CONSUMER_LAB",
        "BOUNDED_LOCAL_DISCOVERY_EXACT_MAC",
        "CONFIRM_CONSUMER_LAB",
        "SEALED_RUNTIME_REQUIRED",
        "HOME_LAB_NETWORK_AUTHORITY_REJECTED",
        "prepared_commit_verified",
        "MaxPresencePasses = 2",
        "NeighborSettleMs = 1000",
        "presence_passes_run",
        "reacquisition_exhausted",
        "HOME_LAB_EXACT_MAC_NOT_FOUND_AFTER_REACQUISITION",
        "if ($null -ne $selectedConfig.NetProfile)",
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

    # Structural/executable regression: direct PowerShell invocation cannot exceed
    # the documented two-pass ceiling. The negative mutation must fail this owner.
    assert_presence_pass_contract(discover_ps)
    widened = discover_ps.replace("[ValidateRange(1,2)]", "[ValidateRange(1,3)]", 1)
    widened_rejected = False
    try:
        assert_presence_pass_contract(widened)
    except AssertionError:
        widened_rejected = True
    assert widened_rejected, "widened three-pass fixture unexpectedly satisfied the contract"

    # Producer -> registry parity: derive the producer template from the executable
    # format string, then require the canonical registry to name the same artifact.
    artifact_entries = {entry["id"]: entry for entry in artifacts["artifacts"]}
    produced = "survey/output/hh-cc-reader/" + producer_receipt_template(discover_ps)
    registered = artifact_entries["hh-cc-reader-home-lab-discovery-result"]["path"]
    assert registered == produced, f"home-lab receipt registry drift: {registered} != {produced}"
    assert registered.endswith("-<timestamp>-<8hex>.json")
    assert registered != "survey/output/hh-cc-reader/hh-cc-reader-home-lab-discovery-<timestamp>.json"

    # AD doctrine reconciliation: this private-LAN exact-MAC lane must not silently
    # become an enterprise directory probe. It explicitly records that AD is not
    # verified and routes separate AD needs to the canonical AD workflow.
    assert "NOT_AD_VERIFIED" in discover_ps
    assert "NOT_APPLICABLE_TO_EXACT_MAC_CONSUMER_LAB_REACQUISITION" in discover_ps
    assert "NOT_AD_VERIFIED" in docs
    for forbidden_ad_call in ("Get-ADComputer", "DirectorySearcher", "[ADSI]"):
        assert forbidden_ad_call not in discover_ps
    assert "home-lab-state-{0}.json" in checkpoint_ps
    assert "NETWORK_CHECKPOINT_NO_ACTIVE_IPV4" in checkpoint_ps
    assert "before_checkpoint" in checkpoint_ps

    # Null-NetProfile regression (2026-10-01): strict mode throws on
    # `$config.NetProfile.Name` when an active adapter exposes a null profile.
    assert "if ($null -ne $config.NetProfile)" in checkpoint_ps, (
        "checkpoint must guard null NetProfile before reading .Name"
    )
    # Null-pipe regression: filter null gateways before reading .NextHop.
    assert "$config.IPv4DefaultGateway | Where-Object { $null -ne $_ } |" in checkpoint_ps, (
        "checkpoint must filter null gateway entries before reading .NextHop"
    )
    # Some hosts expose route rows without PolicyStore; feature-detect it.
    assert "PSObject.Properties['PolicyStore']" in checkpoint_ps, (
        "checkpoint must feature-detect PolicyStore before reading it"
    )

    assert "PROTECTED_ENTERPRISE" in docs
    assert "AUTHORIZED_CONSUMER_LAB" in docs
    assert "does **not** weaken" in docs
    assert "C:\\SASAL\\Discover-HHCCReaderHomeLab.cmd RUN_ID CONFIRM_CONSUMER_LAB [EXPECTED_MAC]" in docs
    assert "Known approved IPv4" in docs
    assert "do not throw it away and start subnet discovery" in docs
    assert "at most two bounded presence attempts per local host" in docs
    assert "HOME_LAB_EXACT_MAC_NOT_FOUND_AFTER_REACQUISITION" in docs
    assert "C:\\SASAL\\Discover-HHCCReaderHomeLab.cmd RUN_ID\n" not in docs
    assert "for ($pass = 1; $pass -le $MaxPresencePasses; $pass++)" in discover_ps
    assert "Start-Sleep -Milliseconds $NeighborSettleMs" in discover_ps
    assert "network_profile = $networkProfileName" in discover_ps
    assert "merchanthelp.bankofamerica.com/Pax-Terminal-Configuration" in docs

    print("[PASS] H&H network-switch checkpoint is a tracked CMD workflow")
    print("[PASS] Authorized consumer-lab discovery is bounded and exact-MAC gated")
    print("[PASS] PAX-family alpha-input planning is codified without tracked credentials")
    print("[PASS] Home-lab workflow registers commands, outcomes, and ignored evidence")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
