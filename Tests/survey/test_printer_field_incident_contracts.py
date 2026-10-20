#!/usr/bin/env python3
"""No-network cross-platform contract for technician-originated printer incident routing.

Behavioral Windows PowerShell fixtures are owned by printer-field-incident.yml.
"""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CMD = ROOT / "Report-NorthwellPrinter-Issue.cmd"
ENGINE = ROOT / "scripts/Invoke-SasPrinterFieldIncident.ps1"
RUNBOOK = ROOT / "docs/field/PRINTER-INCIDENT-AGENT-RUNBOOK.md"
POLICY = ROOT / "harness/api/printer-field-incident-route.v1.json"
ROUTING = ROOT / "harness/api/agent-routing-manifest.json"
SKILL = ROOT / ".claude/skills/field-workflow/SKILL.md"
AGENTS = ROOT / "AGENTS.md"
INSTALLER = ROOT / "scripts/Install-SasUniversalFieldLauncher.ps1"
MAP = ROOT / "CODEBASE_MAP.md"
SOURCE_PAGE = ROOT / "docs/field/NORTHWELL-PRINTER-DOWNLOAD.html"
WORKFLOW = ROOT / ".github/workflows/printer-field-incident.yml"

SYMTOMS = {
    "mapping-failed", "standard-user-missing", "fallback-staging",
    "task-logon", "startup-cleanup", "launcher-download", "unknown",
}

def read(path: Path) -> str:
    assert path.is_file(), f"missing contract file: {path}"
    return path.read_text(encoding="utf-8")

def test_agent_reads_any_technician_message() -> None:
    policy = json.loads(read(POLICY))
    router = json.loads(read(ROUTING))
    field = next(x for x in router["triggers"] if x["id"] == "field-workflow-trigger")
    assert field["target"] == "field-workflow"
    assert {"SAS PRINTER INCIDENT", "standard user can't see printer", "printer fallback failed"} <= set(field["deterministic_task_signals"])
    assert set(policy["symptoms"]) == SYMTOMS
    assert all(x["owner"] and x["next"] for x in policy["symptoms"].values())
    assert "PRINTER-INCIDENT-AGENT-RUNBOOK.md" in read(AGENTS)
    assert "PRINTER-INCIDENT-AGENT-RUNBOOK.md" in read(SKILL)
    assert "printer-field-incident-route.v1.json" in read(MAP)
    assert "TokenCorridor" in read(RUNBOOK)
    for prompt in ("P04", "P07", "P08", "P82"):
        assert prompt in read(RUNBOOK), prompt

def test_cmd_is_nonprivileged_offline_collector() -> None:
    cmd = read(CMD).lower()
    assert "invokes" not in cmd
    assert "invoke-sasprinterfieldincident.ps1" in cmd
    assert "localappdata" in cmd
    for forbidden in ("-executionpolicy bypass", "runas", "schtasks", "reg add", "powershell -enc", "invoke-webrequest", "https://"):
        assert forbidden not in cmd, forbidden
    assert "sas_symptom" in cmd
    assert "start \"\" notepad.exe" in cmd

def test_script_never_publishes_raw_information() -> None:
    src = read(ENGINE)
    for required in (
        "NO_EXTERNAL_PUSH", "NOT_OBSERVED_BY_INTAKE", "latest-handoff.txt",
        "sas-finding-event/v1", "sas-printer-technician-incident/v1",
        "incident.v1.json", "agent-handoff.txt", "finding-input.v1.json",
        "PRIVATE_OUTPUT_REQUIRED", "EVIDENCE_NOT_LOCAL",
        "LOCAL_PRIOR_USER_RECEIPT_EXISTS_NOT_CURRENT_PROOF",
    ):
        assert required in src, required
    for forbidden in ("Invoke-WebRequest", "Invoke-RestMethod", "Invoke-Command", "Start-Process",
                      "Get-Credential", "Add-Printer", "Remove-Printer", "Set-ExecutionPolicy",
                      "schtasks.exe", "reg.exe", "curl.exe", "Get-NetPrinter"):
        assert forbidden not in src, forbidden
    assert 'Printers = $summary.Printers' not in src
    assert "Computers = $summary.Computers" not in src
    assert "UserName = $receipt.UserName" not in src
    assert "UserSid = $receipt.UserSid" not in src

def test_installed_entrypoint_uses_existing_universal_owner() -> None:
    installer = read(INSTALLER)
    assert "sourcePrinterIncidentCmd" in installer
    assert "sourcePrinterIncidentScript" in installer
    assert "printerIncidentCmdDestination" in installer
    assert "printerIncidentScriptDestination" in installer
    assert "Copy-Item -LiteralPath $sourcePrinterIncidentCmd" in installer
    assert "Copy-Item -LiteralPath $sourcePrinterIncidentScript" in installer

def test_ci_runs_static_and_windows_behavior() -> None:
    workflow = read(WORKFLOW)
    assert "windows-latest" in workflow
    assert "PowerShell" in workflow
    assert "test_printer_field_incident_contracts.py" in workflow
    assert "test_agent_routing_manifest_contracts.py" in workflow
    assert "NO_EXTERNAL_PUSH" in workflow
    assert "WKS-SYNTH-LEAK" in workflow
    assert "SECRET-QUEUE-LEAK" in workflow

if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print("PASS: printer field incident routing and privacy static contracts")
