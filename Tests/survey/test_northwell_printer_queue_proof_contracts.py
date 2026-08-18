#!/usr/bin/env python3
"""Static contracts for the Northwell printer operational-check application."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OP_ENGINE = ROOT / "scripts" / "Invoke-SasNorthwellPrinterQueueOperationalCheck.ps1"
DIAG_ENGINE = ROOT / "scripts" / "Invoke-SasNorthwellPrinterQueueProof.ps1"
LAUNCHER = ROOT / "Prove-NorthwellPrinter-Queue.cmd"
LOG_LAUNCHER = ROOT / "Open-NorthwellPrinter-Queue-Proof-Logs.cmd"
POLICY = ROOT / "harness" / "api" / "copy-safe-operator-command-policy.json"
DOC = ROOT / "docs" / "COPY_SAFE_OPERATOR_COMMANDS.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required surface: {path}"
    return path.read_text(encoding="utf-8-sig")


def test_surfaces_and_policy_registration() -> None:
    for path in (OP_ENGINE, DIAG_ENGINE, LAUNCHER, LOG_LAUNCHER, POLICY, DOC):
        assert path.is_file(), f"missing surface: {path}"
    data = json.loads(POLICY.read_text(encoding="utf-8"))
    capsule = next(item for item in data["registered_capsules"] if item["id"] == "northwell.printer.queue-proof")
    assert capsule["launcher"] == "Prove-NorthwellPrinter-Queue.cmd"
    assert capsule["engine"] == "scripts/Invoke-SasNorthwellPrinterQueueOperationalCheck.ps1"
    assert capsule["diagnostic_engine"] == "scripts/Invoke-SasNorthwellPrinterQueueProof.ps1"
    assert capsule["logs_launcher"] == "Open-NorthwellPrinter-Queue-Proof-Logs.cmd"
    assert capsule["direct_ip_mapping"] is False
    assert capsule["default_test_page"] is False
    assert capsule["mutation"] == "none"
    assert capsule["latest_result"].endswith("latest.json")
    assert capsule["latest_summary"].endswith("latest.txt")


def test_launcher_is_no_print_and_window_safe() -> None:
    text = read(LAUNCHER)
    assert "Invoke-SasNorthwellPrinterQueueOperationalCheck.ps1" in text
    assert "NO TEST PAGE" in text
    assert "This launcher does NOT print a test page" in text
    assert "This window will NOT close automatically" in text
    assert "latest.txt" in text
    assert "latest.json" in text
    assert "Open-NorthwellPrinter-Queue-Proof-Logs.cmd" in text
    assert "PrintTestPage" not in text
    assert "Issue one bounded Windows test page" not in text
    assert not re.search(r"(?im)^\s*PS\s+[^>\r\n]+>", text)
    assert not re.search(r"(?m)^\s*>>\s*", text)


def test_operational_engine_never_prints_and_preserves_evidence() -> None:
    text = read(OP_ENGINE)
    assert "sas-northwell-printer-queue-operational/v1" in text
    assert "no_test_page_requested = $true" in text
    assert "direct_ip_mapping_performed = $false" in text
    assert "PrintTestPage" not in text
    assert "-PrintTestPage" not in text
    assert "latest.json" in text
    assert "latest.txt" in text
    assert "LATEST-PATH.txt" in text
    assert "latest-diagnostic.stdout.txt" in text
    assert "latest-diagnostic.stderr.txt" in text
    assert "Get-SasPriorPhysicalProof" in text
    assert "QUEUE_OPERATIONAL_PHYSICAL_PROOF_PRESERVED" in text
    assert "QUEUE_OPERATIONAL_STATUS_TELEMETRY_DEGRADED" in text
    assert "REMOTE_STATUS_TELEMETRY_DISAGREES_WITH_LOCAL_QUEUE" in text


def test_diagnostic_engine_remains_bounded_and_nonmapping() -> None:
    text = read(DIAG_ENGINE)
    assert "Printer must be one shared queue in UNC form" in text
    assert "Printer server must be a queue server hostname, not an IP address" in text
    assert "direct_ip_mapping_performed = $false" in text
    assert "Test-SasTcpBounded" in text
    assert "Get-Printer -ComputerName" in text
    assert "Get-NetTCPConnection -RemoteAddress" in text
    assert "Start-SasChildPowerShell" in text
    assert "process.Kill()" in text
    assert "Add-Printer" not in text
    assert "Add-PrinterPort" not in text


def test_logs_are_recoverable_after_terminal_closure() -> None:
    text = read(LOG_LAUNCHER)
    assert "latest.txt" in text
    assert "latest.json" in text
    assert "LATEST-PATH.txt" in text
    assert "explorer.exe" in text
    assert "notepad.exe" in text


def test_docs_forbid_repeat_print_and_parent_shell_exit() -> None:
    text = read(DOC)
    assert "The normal launcher never prints a test page." in text
    assert "Do not append `exit $LASTEXITCODE`" in text
    assert "Open-NorthwellPrinter-Queue-Proof-Logs.cmd" in text
    assert "latest.txt" in text
    assert "latest.json" in text


def main() -> None:
    tests = [
        test_surfaces_and_policy_registration,
        test_launcher_is_no_print_and_window_safe,
        test_operational_engine_never_prints_and_preserves_evidence,
        test_diagnostic_engine_remains_bounded_and_nonmapping,
        test_logs_are_recoverable_after_terminal_closure,
        test_docs_forbid_repeat_print_and_parent_shell_exit,
    ]
    for test in tests:
        test()
        print(f"PASS: {test.__name__}")
    print(f"PASS: {len(tests)} Northwell printer operational-check contract groups")


if __name__ == "__main__":
    main()
