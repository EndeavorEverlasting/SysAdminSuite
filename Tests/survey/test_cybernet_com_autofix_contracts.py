#!/usr/bin/env python3
"""Static contracts for the local Cybernet COM AutoFix.

These tests validate tracked safety boundaries and operator entrypoints. They do
not execute registry, PnP, restart, or device-manager changes.
"""

from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts" / "Invoke-CybernetComPortAutoFix.ps1"
STARTER_PATH = REPO_ROOT / "scripts" / "Start-CybernetComPortAutoFix.ps1"
LAUNCHER_PATH = REPO_ROOT / "Run-CybernetComPortAutoFix.cmd"
DRYRUN_LAUNCHER_PATH = REPO_ROOT / "Run-CybernetComPortAutoFix-DryRun.cmd"
HELP_LAUNCHER_PATH = REPO_ROOT / "Run-CybernetComPortHelp.cmd"
PACK_PATH = REPO_ROOT / "configs" / "hotfix-command-packs" / "cybernet-com-port-repair.pack.json"
DOC_PATH = REPO_ROOT / "docs" / "field-hotfixes" / "cybernet-com-port-autofix.md"
QR_DOC_PATH = REPO_ROOT / "docs" / "field-hotfixes" / "cybernet-com-port-qr-pack.md"
READINESS_DOC_PATH = REPO_ROOT / "docs" / "handoff" / "cybernet-com-autofix-release-readiness.md"
PARSER_PATH = REPO_ROOT / "scripts" / "Test-CybernetComPortAutoFixParser.ps1"
INSPECTOR_PATH = REPO_ROOT / "scripts" / "Inspect-CybernetComPortAutoFixEvidence.ps1"
HELP_PATH = REPO_ROOT / "scripts" / "Show-CybernetComPortHelp.ps1"
READINESS_TEST_PATH = REPO_ROOT / "Tests" / "Pester" / "CybernetComPortAutoFixReadiness.Tests.ps1"


def read(path: Path) -> str:
    assert path.exists(), f"missing file: {path}"
    return path.read_text(encoding="utf-8")


def load_pack() -> dict:
    return json.loads(read(PACK_PATH))


def test_technician_launchers_are_bounded_and_do_not_bypass_policy() -> None:
    apply_launcher = read(LAUNCHER_PATH)
    dry_launcher = read(DRYRUN_LAUNCHER_PATH)
    help_launcher = read(HELP_LAUNCHER_PATH)

    assert "Mode: APPLY + RESTART" in apply_launcher
    assert "Mode: DRY RUN ONLY" in dry_launcher
    assert "Start-CybernetComPortAutoFix.ps1" in apply_launcher
    assert "Start-CybernetComPortAutoFix.ps1" in dry_launcher
    assert "-Mode Apply" in apply_launcher
    assert "-Mode DryRun" in dry_launcher

    for launcher in (apply_launcher, dry_launcher):
        assert "set \"SAS_COM_AUTOFIX_ARGS=%*\"" in launcher
        assert "if defined SAS_COM_AUTOFIX_ARGS" in launcher
        assert "exit /b 2" in launcher
        assert "-ExecutionPolicy Bypass" not in launcher
        invocation = next(
            line for line in launcher.splitlines() if "Start-CybernetComPortAutoFix.ps1" in line
        )
        assert "%*" not in invocation

    assert "Show-CybernetComPortHelp.ps1" in help_launcher
    assert "-ExecutionPolicy Bypass" not in help_launcher


def test_elevation_helper_is_synchronous_quote_bounded_and_mode_locked() -> None:
    starter = read(STARTER_PATH)

    assert "ValidateSet('DryRun', 'Apply')" in starter
    assert "Test-RunningAsAdministrator" in starter
    assert "Start-Process" in starter
    assert "-Verb RunAs" in starter
    assert "-Wait" in starter
    assert "-PassThru" in starter
    assert "exit $process.ExitCode" in starter
    assert "-ExecutionPolicy" not in starter
    assert "& $corePath -Apply -Restart" in starter
    assert "& $corePath" in starter
    assert "-Force" not in starter


def test_autofix_script_is_local_admin_bounded_and_evidence_first() -> None:
    content = read(SCRIPT_PATH)

    assert "Test-RunningAsAdministrator" in content
    assert "Run this from an elevated Command Prompt" in content
    assert "C:\\Temp\\CybernetCOM" in content
    for artifact in [
        "serialcomm-before.txt",
        "ports-before.txt",
        "multiport-before.txt",
        "pnp-before.json",
        "COMNameArbiter-before.reg",
        "port-mapping-plan.json",
        "autofix-summary.json",
        "autofix-transcript.txt",
    ]:
        assert artifact in content


def test_autofix_script_is_factored_for_future_posture_changes() -> None:
    content = read(SCRIPT_PATH)
    required_functions = [
        "Initialize-ComAutoFixEvidence",
        "Write-ComAutoFixProgress",
        "Invoke-ComAutoFixRegistryExport",
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
    assert "Write-Progress" in content
    assert "Phase {0}/9" in content
    for phase in [
        "Evidence setup",
        "Before-state capture",
        "Eligibility checks",
        "Registry backup",
        "Mapping plan",
        "Apply changes",
        "After-state capture",
        "Summary",
        "Restart",
    ]:
        assert phase in content
    for status in ["COMPLETE", "DRY RUN COMPLETE", "FAILED", "REBOOTING"]:
        assert status in content


def test_autofix_only_targets_known_four_port_pattern() -> None:
    content = read(SCRIPT_PATH)

    assert "Expected the known failed map COM3-COM6" in content
    assert "Expected exactly 4 active Communications Port devices" in content
    assert "FINTEK or multi-port serial device was not detected" in content
    assert "already COM1-COM4" in content
    assert "if (-not $State.FintekPresent -and -not $Force)" in content
    assert "if ($State.Ports.Count -ne 4)" in content
    assert "if ($currentSet -ne '3,4,5,6')" in content
    assert "This invariant cannot be overridden with -Force." in content


def test_registry_is_backed_up_and_validated_before_mutation() -> None:
    content = read(SCRIPT_PATH)

    for fragment in [
        "Invoke-ComAutoFixRegistryExport",
        "Export-ComAutoFixRegistryBackup",
        "COMNameArbiter-before.reg",
        "device-parameters-before-{0:00}.reg",
        "reg.exe export",
        "$LASTEXITCODE",
        "Registry export failed with exit code",
        "Registry export did not create the expected backup file",
        "Registry export created an empty backup file",
        "registry_backups",
        "if (-not $registryBackups.validated)",
    ]:
        assert fragment in content

    backup_call = content.index("$registryBackups = Export-ComAutoFixRegistryBackup")
    validation_gate = content.index("if (-not $registryBackups.validated)", backup_call)
    reset_call = content.index("Invoke-CybernetComArbiterReset -RunDir", backup_call)
    mapping_call = content.index("Set-CybernetComPortMapping -Mapping", backup_call)
    assert backup_call < validation_gate < reset_call < mapping_call


def test_arbiter_reset_fails_closed_before_portname_mutation() -> None:
    content = read(SCRIPT_PATH)
    start = content.index("function Invoke-CybernetComArbiterReset")
    end = content.index("function Set-CybernetComPortMapping", start)
    reset_block = content[start:end]

    assert "reg.exe add" in reset_block
    assert "$exitCode = $LASTEXITCODE" in reset_block
    assert "if ($exitCode -ne 0)" in reset_block
    assert "COM Name Arbiter reset failed with exit code" in reset_block


def test_no_remote_execution_or_public_bootstrap() -> None:
    combined = "\n".join(
        [read(SCRIPT_PATH), read(STARTER_PATH), read(LAUNCHER_PATH), read(DRYRUN_LAUNCHER_PATH)]
    )
    for fragment in [
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
    ]:
        assert fragment not in combined, f"AutoFix must not include {fragment!r}"


def test_qr_pack_exposes_autofix_as_step_12() -> None:
    pack = load_pack()
    steps = pack["sequence"]
    step12 = steps[-1]

    assert pack["version"] == "1.1.0"
    assert pack["autofix_entrypoint"] == "Run-CybernetComPortAutoFix.cmd"
    assert len(steps) == 12
    assert [item["step"] for item in steps] == [f"{i:02d}" for i in range(1, 13)]
    assert step12["command_id"] == "cybernet.com.12_run_autofix"
    assert step12["cmd_payload"] == "Run-CybernetComPortAutoFix.cmd"
    assert step12["risk_level"] == "medium"


def test_docs_explain_boundaries_progress_backups_and_readiness_marker() -> None:
    doc = read(DOC_PATH)
    qr_doc = read(QR_DOC_PATH)
    readiness = read(READINESS_DOC_PATH)

    for fragment in [
        "Run-CybernetComPortAutoFix.cmd",
        "Run-CybernetComPortAutoFix-DryRun.cmd",
        "COM3",
        "COM6",
        "COM1",
        "COM4",
        "No remote execution",
        "No admin-box target mutation",
        "No SmartLynx or final app install",
        "No USB/COM driver replacement",
        "progress bar",
        "DRY RUN COMPLETE",
        "before any COM registry mutation",
        "device-parameters-before-01.reg",
    ]:
        assert fragment.lower() in doc.lower()

    assert "Run automated COM AutoFix" in qr_doc
    assert "HOLD - DO NOT MERGE" in readiness
    assert "GO|READY" in read(HELP_PATH)


def test_readiness_helpers_prevent_false_results_and_allow_noop_evidence() -> None:
    parser = read(PARSER_PATH)
    inspector = read(INSPECTOR_PATH)
    readiness_test = read(READINESS_TEST_PATH)

    assert "[System.Management.Automation.Language.Parser]::ParseFile" in parser
    assert "$parseErrors.Count -gt 0" in parser
    assert "PARSE OK" in parser

    assert "autofix-summary.json" in inspector
    assert "if ($summary.status -eq 'already-correct')" in inspector
    assert "ALREADY CORRECT" in inspector
    assert "if ($null -ne $summary.registry_backups)" in inspector
    assert "REGISTRY BACKUPS VALIDATED" in inspector
    assert "Set-ItemProperty" not in inspector
    assert "reg.exe" not in inspector

    assert "parses the AutoFix script without shell interpolation" in readiness_test
    assert "fails clearly instead of reusing stale state" in readiness_test


def main() -> None:
    tests = [
        test_technician_launchers_are_bounded_and_do_not_bypass_policy,
        test_elevation_helper_is_synchronous_quote_bounded_and_mode_locked,
        test_autofix_script_is_local_admin_bounded_and_evidence_first,
        test_autofix_script_is_factored_for_future_posture_changes,
        test_autofix_script_has_progress_and_unambiguous_final_statuses,
        test_autofix_only_targets_known_four_port_pattern,
        test_registry_is_backed_up_and_validated_before_mutation,
        test_arbiter_reset_fails_closed_before_portname_mutation,
        test_no_remote_execution_or_public_bootstrap,
        test_qr_pack_exposes_autofix_as_step_12,
        test_docs_explain_boundaries_progress_backups_and_readiness_marker,
        test_readiness_helpers_prevent_false_results_and_allow_noop_evidence,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} Cybernet COM AutoFix static contracts")


if __name__ == "__main__":
    main()
