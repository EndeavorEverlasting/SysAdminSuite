#!/usr/bin/env python3
"""Static contracts for the CMD-first machine-info field path."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CMD_FIRST_TEST = "Tests/survey/test_field_guide_cmd_first_contracts.py"
MACHINE_INFO_TEST = "Tests/survey/test_machine_info_cmd_contracts.py"


def read(path: str) -> str:
    target = ROOT / path
    assert target.is_file(), f"missing machine-info authority: {path}"
    return target.read_text(encoding="utf-8-sig")


def by_id(items: list[dict], item_id: str) -> dict:
    for item in items:
        if item.get("id") == item_id:
            return item
    raise AssertionError(f"missing manifest owner: {item_id}")


def main() -> int:
    cmd = read("Get-MachineInfo.cmd")
    collector = read("GetInfo/Get-MachineInfo.ps1")
    runner = read("scripts/Invoke-SasMachineInfo.ps1")
    universal = read("scripts/Invoke-SasUniversalField.ps1")
    network = read("scripts/Invoke-SasNetworkAwareField.ps1")
    installer = read("scripts/Install-SasUniversalFieldLauncher.ps1")
    docs = read("docs/MACHINE_INFO_CMD.md")
    printer_docs = read("START-HERE-NORTHWELL-PRINTER-MAPPING.md")
    workflow = read(".github/workflows/machine-info-cmd-contracts.yml")
    offline = read("tests/survey/run_offline_survey_tests.sh")
    capability = json.loads(read("harness/api/agent-capability-manifest.json"))
    routing = json.loads(read("harness/api/agent-routing-manifest.json"))

    for marker in (
        'call "%~dp0sas.cmd" machineinfo %*',
        'scripts\\Invoke-SasNetworkAwareField.ps1" refresh',
        '%ProgramData%\\SysAdminSuite\\bin\\sas.cmd',
        '%LOCALAPPDATA%\\SysAdminSuite\\bin\\sas.cmd',
        'set "SAS_MACHINEINFO_OPEN_OUTPUT=1"',
    ):
        assert marker in cmd, f"machine-info CMD missing marker: {marker}"
    stale_direct = 'Invoke-SasNetworkAwareField.ps1" machineinfo %*'
    assert stale_direct not in cmd, "repository/runtime CMD must refresh before installed MachineInfo handoff"
    for forbidden in ("C:\\Users\\", "OneDrive", "WBK333", "ORT04"):
        assert forbidden not in cmd, f"machine-info CMD contains user/site-specific authority: {forbidden}"

    for marker in (
        "NetworkAdapters",
        "Index={0}|Description={1}|IPv4={2}|MAC={3}|Gateway={4}|DHCP={5}",
        "legacy aggregate columns",
        "never infer interface role",
        "Select-Object HostName,Serial,NetworkAdapters,MonitorSerials,Status,ErrorMessage",
    ):
        assert marker in collector, f"machine-info collector missing adapter-provenance contract: {marker}"
    assert "IPAddress       = ($ipv4s -join ';')" in collector, "legacy IPAddress compatibility column was removed"
    assert "MACAddress      = ($macs -join ';')" in collector, "legacy MACAddress compatibility column was removed"
    for status in ("Query Failed", "Offline"):
        status_at = collector.index(f"Status          = '{status}'")
        shape = collector[max(0, status_at - 500) : status_at + 250]
        assert "NetworkAdapters = ''" in shape, f"{status} output shape lost NetworkAdapters"

    for marker in (
        "legacy aggregate columns",
        "not primary/secondary fields",
        "NetworkAdapters",
        "which IP belongs to which interface?",
        "target PCs are hostnames/FQDNs and printers are shared queue identities",
        "Printer IP mapping remains forbidden",
        "%LOCALAPPDATA%\\SysAdminSuite\\bin\\sas.cmd",
        "unique suffix prevents concurrent runs",
        "canonical `sas refresh` transaction",
        "stages that collector and its HTML helper",
        "File mode validates its local target file",
    ):
        assert marker in docs, f"machine-info docs missing network/runtime semantics: {marker}"
    for marker in (
        "Target PCs use hostnames/FQDNs, not IP addresses.",
        "Never map by printer IP address.",
    ):
        assert marker in printer_docs, f"printer mapping identity contract regressed: {marker}"

    for marker in (
        "'sas-machine-info-run/v1'",
        "SysAdminSuite\\jobs\\MachineInfo",
        "GetInfo\\Get-MachineInfo.ps1",
        "C:\\SASAL\\GetInfo\\Get-MachineInfo.ps1",
        "SysAdminSuite\\repo-root.txt",
        "[guid]::NewGuid().ToString('N').Substring(0,8)",
        "MACHINE_INFO_TARGET_SET_MISMATCH",
        "exact_target_set_validated = $true",
        "target_mutation_performed = $false",
        "MACHINE_INFO_COMPLETED",
    ):
        assert marker in runner, f"machine-info runner missing marker: {marker}"
    for mutation in ("Restart-Computer", "Add-Printer", "Remove-Printer", "Set-WmiInstance", "Invoke-Command"):
        assert mutation not in runner, f"machine-info runner must remain read-only: {mutation}"

    assert "Machine inventory: sas machineinfo HOST01 [HOST02 ...]" in universal
    assert "'machineinfo'" in universal and "Invoke-SasMachineInfo.ps1" in universal
    assert 'Assert-SasProtectedForAction -Purpose $purpose' in universal

    for marker in (
        "Test-SasMachineInfoTargetFileForNetworkTransition",
        "Test-SasMachineInfoShapeForNetworkTransition",
        "Get-Content -LiteralPath $fullPath -TotalCount 501",
        "$targets.Count -gt 500",
        "@('machineinfo','machine-info')",
        "$intent = 'ProtectedNorthwell'",
        "StartsWith('\\\\',[StringComparison]::Ordinal)",
    ):
        assert marker in network, f"machine-info network pre-transition validation missing: {marker}"

    for marker in (
        "$sourceMachineInfoRunner",
        "$sourceMachineInfoCore",
        "$sourceMachineInfoHtmlHelper",
        "$sourceMachineInfoTechnicianCmd",
        "$machineInfoRunnerDestination",
        "$machineInfoCoreDestination",
        "$machineInfoHtmlHelperDestination",
        "$machineInfoTechnicianCmdDestination",
        "Get-MachineInfo.cmd",
        "Invoke-SasMachineInfo.ps1",
        "tools\\ConvertTo-SuiteHtml.ps1",
    ):
        assert marker in installer, f"universal installer missing machine-info marker: {marker}"

    for marker in (
        "github.event_name == 'pull_request'",
        "github.event.before",
        "github.sha",
        'git diff --check "$DIFF_BASE" "$DIFF_HEAD"',
        'git rev-parse "${DIFF_HEAD}^"',
    ):
        assert marker in workflow, f"MachineInfo workflow is not event-safe for whitespace proof: {marker}"

    first = docs.index("The technician front door is `Get-MachineInfo.cmd`")
    implementation = docs.index("The underlying collector remains `GetInfo\\Get-MachineInfo.ps1`")
    assert first < implementation, "technician documentation must remain CMD-first"
    assert MACHINE_INFO_TEST in offline
    assert CMD_FIRST_TEST in offline

    field_design = by_id(capability["capabilities"], "field-command-design")
    field_skill = by_id(capability["skills"], "field-workflow")
    field_route = by_id(routing["triggers"], "field-workflow-trigger")
    for owner in (field_design, field_skill, field_route):
        validators = owner.get("validators", [])
        assert CMD_FIRST_TEST in validators, f"CMD-first contract is not registered by {owner['id']}"
        assert MACHINE_INFO_TEST in validators, f"MachineInfo contract is not registered by {owner['id']}"
    for signal in ("machine information", "machine inventory", "get machine info"):
        assert signal in field_route["deterministic_task_signals"], f"missing MachineInfo field-workflow signal: {signal}"

    print("[PASS] Machine Info has a repository-owned CMD front door with freshness handoff")
    print("[PASS] Installed/source launchers route through the universal network-aware SAS command")
    print("[PASS] Machine Info publishes collision-safe ProgramData evidence and validates exact target coverage")
    print("[PASS] Direct installed runner resolves only trusted machine-local controller/runtime authorities")
    print("[PASS] Invalid file targets cannot trigger a protected-network transition")
    print("[PASS] Installed MachineInfo runner carries its collector/helper dependencies")
    print("[PASS] Multi-IP rows carry deterministic per-adapter provenance; legacy aggregates are non-authoritative")
    print("[PASS] Printer mapping remains hostname/shared-queue based and cannot consume MachineInfo IPs as identity")
    print("[PASS] Machine Info remains read-only and protected-network gated")
    print("[PASS] Machine Info CI whitespace proof is valid for PR and main-push event shapes")
    print("[PASS] CMD-first and Machine Info contracts are registered in offline + field-workflow manifests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
