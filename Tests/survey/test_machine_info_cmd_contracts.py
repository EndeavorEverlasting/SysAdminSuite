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
    runner = read("scripts/Invoke-SasMachineInfo.ps1")
    universal = read("scripts/Invoke-SasUniversalField.ps1")
    network = read("scripts/Invoke-SasNetworkAwareField.ps1")
    installer = read("scripts/Install-SasUniversalFieldLauncher.ps1")
    docs = read("docs/MACHINE_INFO_CMD.md")
    offline = read("tests/survey/run_offline_survey_tests.sh")
    capability = json.loads(read("harness/api/agent-capability-manifest.json"))
    routing = json.loads(read("harness/api/agent-routing-manifest.json"))

    for marker in (
        'call "%~dp0sas.cmd" machineinfo %*',
        'scripts\\Invoke-SasNetworkAwareField.ps1',
        'set "SAS_MACHINEINFO_OPEN_OUTPUT=1"',
    ):
        assert marker in cmd, f"machine-info CMD missing marker: {marker}"
    for forbidden in ("C:\\Users\\", "OneDrive", "WBK333", "ORT04"):
        assert forbidden not in cmd, f"machine-info CMD contains user/site-specific authority: {forbidden}"

    for marker in (
        "'sas-machine-info-run/v1'",
        "SysAdminSuite\\jobs\\MachineInfo",
        "GetInfo\\Get-MachineInfo.ps1",
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

    assert "Test-SasMachineInfoShapeForNetworkTransition" in network
    assert "@('machineinfo','machine-info')" in network
    assert "$intent = 'ProtectedNorthwell'" in network

    for marker in (
        "$sourceMachineInfoRunner",
        "$sourceMachineInfoTechnicianCmd",
        "$machineInfoRunnerDestination",
        "$machineInfoTechnicianCmdDestination",
        "Get-MachineInfo.cmd",
        "Invoke-SasMachineInfo.ps1",
    ):
        assert marker in installer, f"universal installer missing machine-info marker: {marker}"

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

    print("[PASS] Machine Info has a repository-owned CMD front door")
    print("[PASS] Installed/source launchers route through the universal network-aware SAS command")
    print("[PASS] Machine Info publishes bounded ProgramData evidence and validates exact target coverage")
    print("[PASS] Machine Info remains read-only and protected-network gated")
    print("[PASS] CMD-first and Machine Info contracts are registered in offline + field-workflow manifests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
