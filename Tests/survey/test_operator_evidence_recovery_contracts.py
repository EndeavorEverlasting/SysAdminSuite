#!/usr/bin/env python3
"""Static contracts for offline operator evidence recovery."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/Show-SasOperatorEvidence.ps1"
CMD = ROOT / "Find-SasEvidence.cmd"
LAUNCHER = ROOT / "scripts/SasPortableLauncher.ps1"
INSTALLER = ROOT / "scripts/Install-SasPortableLauncher.ps1"
DOC = ROOT / "docs/OPERATOR_EVIDENCE_RECOVERY.md"
RUNNER = ROOT / "tests/survey/run_offline_survey_tests.sh"
COMMANDS = ROOT / "harness/api/harness-command-registry.json"
OUTCOMES = ROOT / "harness/api/harness-outcome-registry.json"
ARTIFACTS = ROOT / "harness/api/harness-artifact-registry.json"


def read(path: Path) -> str:
    assert path.is_file(), f"missing evidence recovery surface: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def test_offline_recovery_surface_is_wired() -> None:
    script = read(SCRIPT)
    cmd = read(CMD)
    launcher = read(LAUNCHER)
    installer = read(INSTALLER)
    assert "sas evidence" in launcher
    assert "Find-SasEvidence.cmd" in launcher
    assert "Show-SasOperatorEvidence.ps1" in cmd
    assert "sas evidence Cybernet" in installer
    assert "Network activity: NONE | Target contact: NONE" in script
    for forbidden in (
        "Test-NetConnection",
        "Invoke-WebRequest",
        "Invoke-RestMethod",
        "Start-BitsTransfer",
        "schtasks.exe",
        "shutdown.exe",
        "net use",
    ):
        assert forbidden.lower() not in script.lower(), forbidden


def test_recovery_considers_machine_local_field_ready_and_portable_layouts() -> None:
    script = read(SCRIPT)
    for marker in (
        "$env:LOCALAPPDATA",
        "field-ready*",
        "$env:USERPROFILE",
        "$env:OneDrive",
        "$env:OneDriveCommercial",
        "$env:OneDriveConsumer",
        "SysAdminSuite-portable-onsite",
        "SysAdminSuite-Live",
        "Desktop\\dev",
        "OG Laptop Backup\\Desktop\\dev",
        "repo-root.txt",
        "$env:SAS_REPO_ROOT",
    ):
        assert marker in script, marker
    assert "Get-ChildItem -LiteralPath $searchRoot" in script
    assert "Get-ChildItem -Path $env:USERPROFILE -Recurse" not in script


def test_recovery_knows_profiled_core_artifacts_and_failure_boundary() -> None:
    script = read(SCRIPT)
    for marker in (
        "cybernet_profiled_clinical_core_result.json",
        "profiled clinical-core recovery",
        "cybernet_clinical_core_source_preflight.json",
        "cybernet_deployment_readiness_result.json",
        "cybernet_software_deployment_result.json",
        "autologon_s4u_deployment_result.json",
        "autologon_kerberos_s4u_pilot_result.json",
        "runtime-proof-summary.json",
        "CYBERNET_PROFILED_CLINICAL_CORE_COMPLETED",
        "CYBERNET_PROFILED_CLINICAL_CORE_RECOVERY_VERIFIED",
        "CYBERNET_CLINICAL_CORE_SOURCES_READY",
        "CYBERNET_CLINICAL_CORE_SOURCES_INCOMPLETE",
        "ACTION_REQUIRED",
        "Do not blindly rerun",
    ):
        assert marker in script, marker
    for field in (
        "run_id",
        "target",
        "phase",
        "checkpoint",
        "completed_packages",
        "failed_package",
        "cleanup_succeeded",
        "target_mutated",
        "next_network",
        "next_command",
    ):
        assert field in script, field
    assert "AutoLogon was preserved/untouched" in script
    assert "Imprivata was observational only" in script
    assert "no reboot was performed" in script


def test_action_required_emits_exact_network_and_command_without_target_contact() -> None:
    script = read(SCRIPT)
    assert "NEXT NETWORK:" in script
    assert "NEXT COMMAND:" in script
    assert "sas cybernet Recover $short" in script
    assert "sas cybernet Core $short" in script
    assert "target_mutated" in script
    assert "cleanup_succeeded" in script
    assert "network_activity_performed=$false" in script
    assert "target_contact_performed=$false" in script


def test_recovery_writes_stable_local_pointer_without_committing_evidence() -> None:
    script = read(SCRIPT)
    doc = read(DOC)
    assert "$env:LOCALAPPDATA" in script
    assert "last-evidence.json" in script
    assert "sas-operator-evidence-recovery/v2" in script
    assert "%LOCALAPPDATA%\\SysAdminSuite\\last-evidence.json" in doc
    assert "must not be committed" in doc
    assert "Do not repeat a readiness probe or redeploy a target merely to recreate console output" in doc


def test_harness_registers_evidence_recovery_command_artifact_and_outcome() -> None:
    commands = load(COMMANDS)
    outcomes = load(OUTCOMES)
    artifacts = load(ARTIFACTS)
    command = next(item for item in commands["commands"] if item["id"] == "operator-evidence-recovery")
    assert command["command"] == "sas evidence"
    assert command["network"] is False
    assert command["source_of_truth"] == "scripts/Show-SasOperatorEvidence.ps1"
    contract = next(item for item in outcomes["contracts"] if item["command_id"] == "operator-evidence-recovery")
    assert contract["success_artifact_id"] == "operator-evidence-recovery-index"
    artifact = next(item for item in artifacts["artifacts"] if item["id"] == "operator-evidence-recovery-index")
    assert artifact["tracked"] is False
    assert artifact["contains_live_data"] is True
    assert "LOCALAPPDATA" in artifact["path"]


def test_offline_floor_runs_recovery_contracts() -> None:
    runner = read(RUNNER)
    assert "python3 Tests/survey/test_operator_evidence_recovery_contracts.py" in runner


def test_no_user_specific_literals() -> None:
    combined = "\n".join(read(path) for path in (SCRIPT, CMD, LAUNCHER, INSTALLER, DOC))
    for forbidden in ("pa_rperez26", "WPJ075OPR046", "Cheex", "rperez26@", "rperez@"):
        assert forbidden.lower() not in combined.lower(), forbidden


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: operator evidence recovery contracts ({len(tests)} groups)")