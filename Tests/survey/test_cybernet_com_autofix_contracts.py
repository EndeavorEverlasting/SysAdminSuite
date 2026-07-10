#!/usr/bin/env python3
"""Static contracts for the local Cybernet COM AutoFix.

These tests validate file presence, safety boundaries, and expected local-only behavior.
They do not execute registry or device-manager changes.
"""

from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts" / "Invoke-CybernetComPortAutoFix.ps1"
LAUNCHER_PATH = REPO_ROOT / "Run-CybernetComPortAutoFix.cmd"
DRYRUN_LAUNCHER_PATH = REPO_ROOT / "Run-CybernetComPortAutoFix-DryRun.cmd"
PACK_PATH = REPO_ROOT / "configs" / "hotfix-command-packs" / "cybernet-com-port-repair.pack.json"
DOC_PATH = REPO_ROOT / "docs" / "field-hotfixes" / "cybernet-com-port-autofix.md"
QR_DOC_PATH = REPO_ROOT / "docs" / "field-hotfixes" / "cybernet-com-port-qr-pack.md"


def read(path: Path) -> str:
    assert path.exists(), f"missing file: {path}"
    return path.read_text(encoding="utf-8")


def load_pack() -> dict:
    return json.loads(read(PACK_PATH))


def test_autofix_launcher_runs_apply_restart_with_admin_elevation() -> None:
    launcher = read(LAUNCHER_PATH)

    assert "SysAdminSuite - Cybernet COM Port AutoFix" in launcher
    assert "Mode: APPLY + RESTART" in launcher
    assert "Evidence: C:\\Temp\\CybernetCOM\\autofix_*" in launcher
    assert "net session" in launcher
    assert "Start-Process" in launcher
    assert "-Verb RunAs" in launcher
    assert "Invoke-CybernetComPortAutoFix.ps1" in launcher
    assert "-Apply" in launcher
    assert "-Restart" in launcher
    assert "EXITCODE" in launcher


def test_autofix_dryrun_launcher_does_not_apply_or_restart() -> None:
    launcher = read(DRYRUN_LAUNCHER_PATH)

    assert "SysAdminSuite - Cybernet COM Port AutoFix" in launcher
    assert "Mode: DRY RUN ONLY" in launcher
    assert "This captures evidence and previews the mapping" in launcher
    assert "Invoke-CybernetComPortAutoFix.ps1" in launcher
    assert "-Apply" not in launcher
    assert "-Restart" not in launcher
    assert "EXITCODE" in launcher


def test_autofix_script_is_local_admin_bounded_and_evidence_first() -> None:
    content = read(SCRIPT_PATH)

    assert "Test-RunningAsAdministrator" in content
    assert "Run this from an elevated Command Prompt" in content
    assert "C:\\Temp\\CybernetCOM" in content
    assert "serialcomm-before.txt" in content
    assert "ports-before.txt" in content
    assert "multiport-before.txt" in content
    assert "pnp-before.json" in content
    assert "COMNameArbiter-before.reg" in content
    assert "port-mapping-plan.json" in content
    assert "autofix-summary.json" in content
    assert "autofix-transcript.txt" in content


def test_autofix_script_is_factored_for_future_posture_changes() -> None:
    content = read(SCRIPT_PATH)
    required_functions = [
        "Initialize-ComAutoFixEvidence",
        "Write-ComAutoFixProgress",
        "Export-ComAutoFixRegistryBackup",
        "Get-CybernetComPortState",
        "Test-CybernetComAutoFixEligibility",
        "New-CybernetComMappingPlan",
        "Invoke-CybernetComArbiterReset",
        "Set-CybernetComPortMapping",
        "Write-ComAutoFixSummary",
    ]

    for function_name in required_functions:
        assert f"function {function_name}" in content


def test_autofix_script_has_progress_and_unambiguous_final_statuses() -> None:
    content = read(SCRIPT_PATH)
    phases = [
        "Evidence setup",
        "Before-state capture",
        "Eligibility checks",
        "Registry backup",
        "Mapping plan",
        "Apply changes",
        "After-state capture",
        "Summary",
        "Restart",
    ]

    assert "Write-Progress" in content
    assert "Phase {0}/9" in content
    for phase in phases:
        assert phase in content
    for final_status in ["COMPLETE", "DRY RUN COMPLETE", "FAILED", "REBOOTING"]:
        assert final_status in content


def test_autofix_script_only_targets_known_com3_to_com6_pattern_by_default() -> None:
    content = read(SCRIPT_PATH)

    assert "Expected the known failed map COM3-COM6" in content
    assert "Expected exactly 4 active Communications Port devices" in content
    assert "FINTEK or multi-port serial device was not detected" in content
    assert "COM1, COM2, COM3, COM4" in content
    assert "already COM1-COM4" in content


def test_autofix_script_saves_registry_before_any_portname_changes() -> None:
    content = read(SCRIPT_PATH)

    assert "Export-ComAutoFixRegistryBackup" in content
    assert "COMNameArbiter-before.reg" in content
    assert "device-parameters-before-{0:00}.reg" in content
    assert "reg.exe export" in content
    assert "native_registry_path" in content
    assert "registry_backups" in content
    assert content.index("Export-ComAutoFixRegistryBackup") < content.index("Set-CybernetComPortMapping -Mapping")


def test_autofix_script_resets_arbiter_and_assigns_portname_values() -> None:
    content = read(SCRIPT_PATH)

    assert "COM Name Arbiter" in content
    assert "/v ComDB" in content
    assert "0000000000000000000000000000000000000000000000000000000000000000" in content
    assert "Set-ItemProperty" in content
    assert "-Name PortName" in content
    assert "Device Parameters" in content
    assert "shutdown.exe /r /t 0" in content


def test_autofix_has_no_remote_execution_or_public_bootstrap() -> None:
    combined = "\n".join([
        read(SCRIPT_PATH),
        read(LAUNCHER_PATH),
        read(DRYRUN_LAUNCHER_PATH),
    ])

    forbidden_fragments = [
        "Invoke-Command",
        "New-PSSession",
        "Enter-PSSession",
        "Copy-Item -ToSession",
        "Register-ScheduledTask",
        "http://",
        "https://",
        "password",
        "credential",
        "secret",
        "token",
    ]
    for fragment in forbidden_fragments:
        assert fragment not in combined, f"AutoFix must not include {fragment!r}"


def test_qr_pack_exposes_autofix_as_step_12() -> None:
    pack = load_pack()
    steps = pack["sequence"]
    step12 = steps[-1]

    assert pack["version"] == "1.1.0"
    assert pack["autofix_entrypoint"] == "Run-CybernetComPortAutoFix.cmd"
    assert len(steps) == 12
    assert [item["step"] for item in steps] == [f"{i:02d}" for i in range(1, 13)]
    assert step12["step"] == "12"
    assert step12["command_id"] == "cybernet.com.12_run_autofix"
    assert step12["cmd_payload"] == "Run-CybernetComPortAutoFix.cmd"
    assert step12["risk_level"] == "medium"
    assert "local AutoFix launcher" in step12["expected_result"]


def test_docs_explain_fast_path_boundaries_progress_and_backups() -> None:
    doc = read(DOC_PATH)
    qr_doc = read(QR_DOC_PATH)

    assert "Run-CybernetComPortAutoFix.cmd" in doc
    assert "Run-CybernetComPortAutoFix-DryRun.cmd" in doc
    assert "COM3" in doc and "COM6" in doc
    assert "COM1" in doc and "COM4" in doc
    assert "No remote execution" in doc
    assert "No admin-box target mutation" in doc
    assert "No SmartLynx or final app install" in doc
    assert "No USB/COM driver replacement" in doc
    assert "progress bar" in doc.lower()
    assert "COMPLETE" in doc
    assert "DRY RUN COMPLETE" in doc
    assert "FAILED" in doc
    assert "device-parameters-before-01.reg" in doc
    assert "Run-CybernetComPortAutoFix.cmd" in qr_doc
    assert "Run automated COM AutoFix" in qr_doc


def main() -> None:
    tests = [
        test_autofix_launcher_runs_apply_restart_with_admin_elevation,
        test_autofix_dryrun_launcher_does_not_apply_or_restart,
        test_autofix_script_is_local_admin_bounded_and_evidence_first,
        test_autofix_script_is_factored_for_future_posture_changes,
        test_autofix_script_has_progress_and_unambiguous_final_statuses,
        test_autofix_script_only_targets_known_com3_to_com6_pattern_by_default,
        test_autofix_script_saves_registry_before_any_portname_changes,
        test_autofix_script_resets_arbiter_and_assigns_portname_values,
        test_autofix_has_no_remote_execution_or_public_bootstrap,
        test_qr_pack_exposes_autofix_as_step_12,
        test_docs_explain_fast_path_boundaries_progress_and_backups,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} Cybernet COM AutoFix static contracts")


if __name__ == "__main__":
    main()
