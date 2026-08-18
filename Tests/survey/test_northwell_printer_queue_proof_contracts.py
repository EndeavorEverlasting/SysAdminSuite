#!/usr/bin/env python3
"""Static contracts for the Northwell shared-printer queue proof application."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / "scripts" / "Invoke-SasNorthwellPrinterQueueProof.ps1"
LAUNCHER = ROOT / "Prove-NorthwellPrinter-Queue.cmd"
POLICY = ROOT / "harness" / "api" / "copy-safe-operator-command-policy.json"
DOC = ROOT / "docs" / "COPY_SAFE_OPERATOR_COMMANDS.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required surface: {path}"
    return path.read_text(encoding="utf-8-sig")


def test_surfaces_and_policy_registration() -> None:
    for path in (ENGINE, LAUNCHER, POLICY, DOC):
        assert path.is_file(), f"missing surface: {path}"
    data = json.loads(POLICY.read_text(encoding="utf-8"))
    capsule = next(item for item in data["registered_capsules"] if item["id"] == "northwell.printer.queue-proof")
    assert capsule["launcher"] == "Prove-NorthwellPrinter-Queue.cmd"
    assert capsule["engine"] == "scripts/Invoke-SasNorthwellPrinterQueueProof.ps1"
    assert capsule["direct_ip_mapping"] is False


def test_launcher_is_single_front_door_not_a_transcript() -> None:
    text = read(LAUNCHER)
    assert "Invoke-SasNorthwellPrinterQueueProof.ps1" in text
    assert "Shared printer queue:" in text
    assert "diagnostics only" in text
    assert "No direct-IP printer mapping will occur" in text
    assert not re.search(r"(?im)^\s*PS\s+[^>\r\n]+>", text)
    assert not re.search(r"(?m)^\s*>>\s*", text)


def test_engine_enforces_shared_queue_and_bounds_network_work() -> None:
    text = read(ENGINE)
    assert "Printer must be one shared queue in UNC form" in text
    assert "Printer server must be a queue server hostname, not an IP address" in text
    assert "direct_ip_mapping_performed = $false" in text
    assert "Test-SasTcpBounded" in text
    assert "Get-Printer -ComputerName" in text
    assert "Get-NetTCPConnection -RemoteAddress" in text
    assert "Start-SasChildPowerShell" in text
    assert "WaitForExit($TimeoutSeconds * 1000)" in text
    assert "process.Kill()" in text
    assert "Start-Job" not in text
    assert "PrinterIp -Port 9100" in text
    assert "Add-Printer" not in text
    assert "Add-PrinterPort" not in text


def test_proof_ceiling_distinguishes_ack_from_physical_output() -> None:
    text = read(ENGINE)
    assert "PRINT_REQUEST_ACCEPTED_ONLY" in text
    assert "TEST_PAGE_ACCEPTED_PHYSICAL_OUTPUT_UNPROVEN" in text
    assert "LIVE_PHYSICAL_PRINT_PROOF_PASS" in text
    assert "LIVE_PHYSICAL_OUTPUT_OPERATOR_OBSERVED" in text
    assert "Did a physical test page emerge" in text
    assert "diagnostic_warnings = @()" in text
    assert "REMOTE_QUERY_TIMEOUT_DESPITE_PHYSICAL_PRINT" in text
    assert "TEST_PAGE_CALL_TIMEOUT_DESPITE_PHYSICAL_PRINT" in text

    physical_gate = "if ($PrintTestPage -and $result.physical_output_observed -eq $true)"
    dynamic_failure = "elseif ($result.remote_query.status -eq 'TIMEOUT' -and $rpcDynamicStalled)"
    assert physical_gate in text
    assert dynamic_failure in text
    assert text.index(physical_gate) < text.index(dynamic_failure), (
        "operator-confirmed physical output must outrank diagnostic RPC timeout classifications"
    )


def test_known_rpc_failure_and_dynamic_port_classes_are_preserved() -> None:
    text = read(ENGINE)
    assert "PRINT_RPC_DYNAMIC_PORT_STALLED" in text
    assert "REMOTE_PRINT_QUERY_TIMEOUT" in text
    assert "PRINT_TEST_RPC_SERVER_UNAVAILABLE_1722" in text
    assert "$_.remote_port -ne 135 -and $_.state -eq 'SynSent'" in text
    assert "$_.remote_port -ne 135 -and $_.state -eq 'Established'" in text
    assert "$rpcDynamicStalled = $rpcSynSent -and -not $rpcDynamicEstablished" in text


def test_evidence_is_runtime_local_and_structured() -> None:
    text = read(ENGINE)
    assert "sas-northwell-printer-queue-proof/v1" in text
    assert "LOCALAPPDATA" in text
    assert "SysAdminSuite\\field-runs\\printer-queue-proof" in text
    assert "ConvertTo-Json -Depth 10" in text
    assert "printer-queue-proof-result.json" in text


def main() -> None:
    tests = [
        test_surfaces_and_policy_registration,
        test_launcher_is_single_front_door_not_a_transcript,
        test_engine_enforces_shared_queue_and_bounds_network_work,
        test_proof_ceiling_distinguishes_ack_from_physical_output,
        test_known_rpc_failure_and_dynamic_port_classes_are_preserved,
        test_evidence_is_runtime_local_and_structured,
    ]
    for test in tests:
        test()
        print(f"PASS: {test.__name__}")
    print(f"PASS: {len(tests)} Northwell printer queue proof contract groups")


if __name__ == "__main__":
    main()
