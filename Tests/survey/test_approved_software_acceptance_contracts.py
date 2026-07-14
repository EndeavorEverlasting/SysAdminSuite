#!/usr/bin/env python3
"""Static contracts for approved software application and AutoLogon acceptance extraction."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "configs" / "software-packages" / "approved-apps.json"
ACCEPTANCE = ROOT / "scripts" / "Invoke-SasApprovedSoftwareAcceptance.ps1"
OPERATOR = ROOT / "scripts" / "Start-SasApprovedSoftwareOperator.ps1"
COMPAT = ROOT / "scripts" / "Start-SasAutoDidactInstall.ps1"
DOC = ROOT / "docs" / "APPROVED_SOFTWARE_ACCEPTANCE.md"
WORKFLOW = ROOT / ".github" / "workflows" / "approved-software-acceptance-contracts.yml"
RUNNER = ROOT / "tests" / "survey" / "run_offline_survey_tests.sh"


def read(path: Path) -> str:
    assert path.exists(), f"missing expected file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def test_catalog_codifies_acceptance_profiles() -> None:
    catalog = json.loads(read(CATALOG))
    policy = catalog["catalog_policy"]
    assert policy["acceptance_extraction_after_snapshot"] is True
    assert policy["never_collect_default_password_value"] is True
    assert policy["never_collect_application_command_line"] is True

    packages = {package["id"]: package for package in catalog["packages"]}
    assert set(packages) == {"epic-satellite", "allscripts-touchworks-22-1", "autologon"}
    for package in packages.values():
        acceptance = package["acceptance"]
        assert isinstance(acceptance["application_process_names"], list)
        assert "require_responding_process" in acceptance
        assert "autologon_profile" in acceptance

    autologon = packages["autologon"]["acceptance"]
    assert autologon["autologon_profile"] == "windows_winlogon"
    assert autologon["expected_autologon_user_rule"] == "computer_name"
    assert autologon["require_password_value_name"] is True
    assert autologon["require_current_session_match"] is True
    assert autologon["require_reboot_after_before_snapshot"] is True


def test_acceptance_requires_completed_after_snapshot() -> None:
    content = read(ACCEPTANCE)
    required = [
        "Acceptance extraction requires a completed AFTER snapshot",
        "workflow_status -ne 'after_complete'",
        "after_manifest_path",
        "acceptance-summary.json",
        "workflow_status = 'acceptance_extracted'",
    ]
    for fragment in required:
        assert fragment in content, f"missing after-snapshot gate: {fragment}"


def test_application_launch_observation_is_read_only_and_bounded() -> None:
    content = read(ACCEPTANCE)
    required = [
        "Get-Process -Name $configuredName",
        "process_name",
        "process_id",
        "session_id",
        "executable_path",
        "start_time_utc",
        "responding",
        "main_window_title",
        "launch_observed",
        "At most 12 explicit process names",
        "application_command_line_collected = $false",
        "no_application_launch_or_stop",
    ]
    for fragment in required:
        assert fragment in content, f"missing application evidence contract: {fragment}"

    forbidden = [
        "Start-Process",
        "Stop-Process",
        "Win32_Process.Create",
        "Invoke-CimMethod",
        "CommandLine",
        "SendKeys",
        "WScript.Shell",
    ]
    for fragment in forbidden:
        assert fragment.lower() not in content.lower(), f"forbidden application mutation or command-line collection: {fragment}"


def test_autologon_extraction_never_reads_password_data() -> None:
    content = read(ACCEPTANCE)
    required = [
        "Test-RegistryValueNameSafe",
        "-Name 'DefaultPassword'",
        "default_password_present",
        "default_password_value_collected = $false",
        "configured_password_missing",
        "autologon_ready",
        "current_session_matches_expected",
        "reboot_after_before_snapshot",
        "session_match_after_reboot_observed",
    ]
    for fragment in required:
        assert fragment in content, f"missing AutoLogon evidence contract: {fragment}"

    assert "Get-RegistryValueSafe -Path $winlogon -Name 'DefaultPassword'" not in content
    missing_index = content.index("elseif (-not $passwordPresent) { $configurationStatus = 'configured_password_missing' }")
    ready_index = content.index("else { $configurationStatus = 'autologon_ready' }")
    assert missing_index < ready_index, "password-value presence must be checked before ready classification"


def test_proof_levels_do_not_overclaim_behavior() -> None:
    content = read(ACCEPTANCE)
    required = [
        "FIXTURE_ONLY",
        "MACHINE_EVIDENCE_READY_FOR_TECHNICIAN_REVIEW",
        "TECHNICIAN_ATTESTED_MACHINE_EVIDENCE",
        "process_observation_does_not_prove_business_workflow_success",
        "current_session_match_does_not_alone_prove_automatic_logon",
        "technician_attestation_does_not_prove_actor_identity",
        "runtime_proof = ($proofLevel -eq 'TECHNICIAN_ATTESTED_MACHINE_EVIDENCE')",
    ]
    for fragment in required:
        assert fragment in content, f"missing proof-boundary contract: {fragment}"


def test_operator_exposes_acceptance_without_raw_launch_commands() -> None:
    operator = read(OPERATOR)
    compat = read(COMPAT)
    required_operator = [
        "'Acceptance'",
        "Invoke-SasApprovedSoftwareAcceptance.ps1",
        "Extract application launch and AutoLogon behavior",
        "Invoke-SasAcceptanceAction",
        "ApplicationObserved",
        "AutoLogonObservedAfterReboot",
    ]
    for fragment in required_operator:
        assert fragment in operator, f"missing operator acceptance fragment: {fragment}"
    assert "'Acceptance'" in compat
    assert "ProcessName" in compat
    assert "WindowTitlePattern" in compat


def test_documentation_states_live_proof_boundary() -> None:
    content = read(DOC)
    required = [
        "Run-InstallApprovedSoftware.cmd",
        "Extract application launch and AutoLogon behavior",
        "application process",
        "DefaultPassword value name",
        "never reads the value data",
        "session match after a reboot",
        "does not by itself prove automatic sign-in",
        "TECHNICIAN_ATTESTED_MACHINE_EVIDENCE",
        "one or two approved pilot workstations",
    ]
    for fragment in required:
        assert fragment in content, f"missing acceptance documentation fragment: {fragment}"


def test_workflow_executes_fixture_acceptance_chain() -> None:
    content = read(WORKFLOW)
    required = [
        "test_approved_software_acceptance_contracts.py",
        "Parse acceptance extraction scripts",
        "Capture fixture Before snapshot",
        "Run WhatIf install plan",
        "Capture fixture After snapshot",
        "Extract fixture application and AutoLogon behavior",
        "-Action Acceptance",
        "-ProcessName FixtureApp",
        "acceptance-summary.json",
        "FIXTURE_ONLY",
        "session_match_after_reboot_observed",
        "configured_password_missing",
    ]
    for fragment in required:
        assert fragment in content, f"missing acceptance workflow fragment: {fragment}"


def test_offline_runner_wires_acceptance_contract() -> None:
    content = read(RUNNER)
    assert "python3 Tests/survey/test_approved_software_acceptance_contracts.py" in content


TESTS = {
    "catalog": test_catalog_codifies_acceptance_profiles,
    "after-gate": test_acceptance_requires_completed_after_snapshot,
    "application": test_application_launch_observation_is_read_only_and_bounded,
    "autologon": test_autologon_extraction_never_reads_password_data,
    "proof": test_proof_levels_do_not_overclaim_behavior,
    "operator": test_operator_exposes_acceptance_without_raw_launch_commands,
    "docs": test_documentation_states_live_proof_boundary,
    "workflow": test_workflow_executes_fixture_acceptance_chain,
    "runner": test_offline_runner_wires_acceptance_contract,
}


def main() -> None:
    selected = sys.argv[1:]
    if selected:
        unknown = [name for name in selected if name not in TESTS]
        assert not unknown, f"unknown contract names: {', '.join(unknown)}"
        tests = [(name, TESTS[name]) for name in selected]
    else:
        tests = list(TESTS.items())

    for name, test in tests:
        test()
        print(f"PASS: {name}")
    print(f"PASS: {len(tests)} approved software acceptance contracts")


if __name__ == "__main__":
    main()
