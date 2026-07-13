#!/usr/bin/env python3
"""Static contracts for the AutoLogon deployment workflow."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Invoke-SasAutoLogonDeployment.ps1"
DOC = ROOT / "docs" / "AUTOLOGON_DEPLOYMENT_WORKFLOW.md"


def read(path: Path) -> str:
    assert path.exists(), f"missing required file: {path}"
    return path.read_text(encoding="utf-8")


def test_entrypoint_and_runbook_exist() -> None:
    assert SCRIPT.exists()
    assert DOC.exists()


def test_canonical_package_defaults_are_exact() -> None:
    content = read(SCRIPT)
    assert r"[string]$SoftwareShareRoot = '\\nt2kwb972sms01\'" in content
    assert (
        r"[string]$InstallerRelativePath = "
        r"'packages\AutoLogonSetup\NW_AutoLogon_Setup_x64.exe'"
    ) in content
    assert "NW AutoLogon Setup x64" in content


def test_composes_existing_state_and_install_lanes() -> None:
    content = read(SCRIPT)
    required = (
        "Invoke-SasAutoLogonStateDelta.ps1",
        "Invoke-SasSoftwareInstall.ps1",
        "Mode = 'Before'",
        "Mode = 'After'",
        "Get-SasBaselineEligibility",
        "ELIGIBLE_FOR_INSTALL",
        "SKIP_BASELINE_COLLECTION_FAILED",
        "SKIP_ALREADY_CONFIGURED",
    )
    for fragment in required:
        assert fragment in content, f"missing composition contract: {fragment}"


def test_live_mutation_and_installer_arguments_are_explicitly_gated() -> None:
    content = read(SCRIPT)
    assert "[switch]$AllowTargetMutation" in content
    assert "Refusing target mutation without -AllowTargetMutation" in content
    assert "Live execution requires explicit vendor-validated -InstallerArguments" in content
    assert "-AllowTargetMutation -Confirm:$false" in content


def test_dry_run_and_fixture_are_no_network_contracts() -> None:
    content = read(SCRIPT)
    doc = read(DOC)
    assert "[switch]$FixtureMode" in content
    assert "$WhatIfPreference -and -not $FixtureMode" in content
    assert "target_reads_performed = $false" in content
    assert "target_mutation_performed = $false" in content
    assert "PLANNED_WHATIF" in content
    assert "FIXTURE_PASS" in content
    assert "does not contact the share or any workstation" in doc


def test_workflow_does_not_create_startup_persistence() -> None:
    content = read(SCRIPT)
    doc = read(DOC)
    required = (
        "startup_persistence_created = $false",
        "no_startup_folder_cmd_or_other_persistence",
        "No Startup-folder CMD",
    )
    for fragment in required:
        assert fragment in content or fragment in doc

    forbidden = (
        "\\Startup\\",
        "shell:startup",
        "CurrentVersion\\Run",
        "Register-ScheduledTask",
        "New-ScheduledTask",
        "schtasks.exe",
        "New-Service",
        "sc.exe create",
        "cmdkey",
        "ConvertTo-SecureString",
    )
    lowered = content.lower()
    for fragment in forbidden:
        assert fragment.lower() not in lowered, f"forbidden persistence/credential path: {fragment}"


def test_local_evidence_and_combined_summary_are_declared() -> None:
    content = read(SCRIPT)
    required = (
        "survey/output/autologon_deployment",
        "autologon_deployment_events.jsonl",
        "autologon_deployment_summary.json",
        "operator_handoff.txt",
        "sas-autologon-deployment-summary/v1",
        "confirmed_state_transition_count",
        "cleanup_failure_count",
        "repo_artifact_remaining_count",
        "target_mutation_authorized",
        "install_attempted",
        "default_password_value_collected = $false",
    )
    for fragment in required:
        assert fragment in content, f"missing evidence contract: {fragment}"


def test_runbook_has_fixture_plan_pilot_and_runtime_gates() -> None:
    content = read(DOC)
    required = (
        "Offline end-to-end proof",
        "Request-only dry run",
        "Verify silent installer arguments",
        "Two-workstation approved pilot",
        "Review before expansion",
        "real reboot and observed successful auto-logon",
        "CopyThenInstall",
        "common remote UNC second-hop problem",
    )
    for fragment in required:
        assert fragment in content, f"missing runbook contract: {fragment}"


def main() -> None:
    tests = [
        test_entrypoint_and_runbook_exist,
        test_canonical_package_defaults_are_exact,
        test_composes_existing_state_and_install_lanes,
        test_live_mutation_and_installer_arguments_are_explicitly_gated,
        test_dry_run_and_fixture_are_no_network_contracts,
        test_workflow_does_not_create_startup_persistence,
        test_local_evidence_and_combined_summary_are_declared,
        test_runbook_has_fixture_plan_pilot_and_runtime_gates,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} AutoLogon deployment workflow contracts")


if __name__ == "__main__":
    main()
