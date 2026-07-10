#!/usr/bin/env python3
"""Static contracts for the SysAdminSuite approved software install harness."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
API = ROOT / "harness" / "api" / "sas-harness-api.json"
DOC = ROOT / "docs" / "SOFTWARE_INSTALL_HARNESS.md"
LOCAL_DOC = ROOT / "docs" / "LOCAL_DEVELOPMENT_HARNESS.md"
SCRIPT = ROOT / "scripts" / "Invoke-SasSoftwareInstall.ps1"
SCHEMA = ROOT / "schemas" / "harness" / "software-install-request.schema.json"
RUNNER = ROOT / "tests" / "survey" / "run_offline_survey_tests.sh"
PRE_COMMIT = ROOT / ".githooks" / "pre-commit"
PESTER = ROOT / "Tests" / "Pester" / "SoftwareInstallHarness.Tests.ps1"


def read(path: Path) -> str:
    assert path.exists(), f"missing expected file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def load_json(path: Path) -> dict:
    return json.loads(read(path))


def test_api_manifest_declares_gated_operator_execute_surface():
    api = load_json(API)
    operations = {op["id"]: op for op in api["operations"]}
    op = operations["software_install.operator_execute"]

    assert op["mode"] == "operator_execute"
    assert op["network_activity"] is True
    assert op["target_mutation"] is True

    required_inputs = {
        "approved_targets_csv_or_computer_name",
        "package_name",
        "installer_relative_path",
        "software_share_root",
        "installer_arguments",
        "explicit_allow_target_mutation",
    }
    assert required_inputs <= set(op["inputs"])

    required_guardrails = {
        "Approved_admin_context_only",
        "Approved_read_only_software_share_only",
        "No_credential_collection",
        "No_monitoring_bypass_or_log_suppression",
        "No_unapproved_background_services",
        "No_repo_owned_target_logs_reports_manifests_or_transcripts",
        "Prefer_UNC_direct_install_to_avoid_target_staging",
        "Run_specific_staging_cleanup_attempted_on_all_failure_paths",
        "Prune_empty_SysAdminSuite_target_directories",
        "Local_gitignored_evidence_only",
    }
    assert required_guardrails <= set(op["guardrails"])


def test_document_names_no_artifact_boundary_without_stealth_claims():
    text = read(DOC)
    required = [
        "not stealth tooling",
        "must not suppress Windows logs",
        "no persistent SysAdminSuite-owned staging payloads, reports, manifests, transcripts, scripts, or evidence",
        "installer-owned files, logs, registry changes, caches, services, or records",
        "\\\\nt2kwb972sms01\\",
        "UncDirect",
        "CopyThenInstall",
        "%ProgramData%\\SysAdminSuite\\SoftwareInstall\\<run_id>",
        "Cleanup is attempted from both the normal remote installer `finally` block and the outer failure path",
        "Cleanup failure is a reportable failure",
        "Generated run artifacts stay in gitignored local output paths",
    ]
    for fragment in required:
        assert fragment in text, f"missing software install doc fragment: {fragment}"

    local_text = read(LOCAL_DOC)
    for fragment in [
        "no persistent SysAdminSuite-owned staging payload, log, report, manifest, transcript, script, or evidence",
        "prune empty `ProgramData\\SysAdminSuite\\SoftwareInstall` and `ProgramData\\SysAdminSuite` parent directories",
    ]:
        assert fragment in local_text, f"missing local harness software posture fragment: {fragment}"


def test_script_enforces_approved_source_and_explicit_mutation_gate():
    text = read(SCRIPT)
    required = [
        "[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]",
        "Get-SasApprovedSoftwareShareRoots",
        "approved_software_sources",
        "SoftwareShareRoot is not an approved software source",
        "Resolve-SasApprovedInstallerPath",
        "InstallerRelativePath must be relative",
        "parent-directory traversal",
        "-AllowTargetMutation",
        "Refusing target mutation without -AllowTargetMutation",
        "No targets were supplied",
        "exceeds MaxTargets",
        "New-PSSession -ComputerName $target",
        "Copy-Item -LiteralPath $installerPath -Destination $remoteInstallerPath -ToSession $session -Force",
        "Remove-SasRepoOwnedInstallArtifacts",
        "$remoteRepoCleanup",
        "Remove-Item -LiteralPath $stageRoot -Recurse -Force",
        "run-specific staging path failed validation",
        "pruned_empty_parent_dirs",
        "repo_artifact_remaining_count",
        "operator_handoff.txt",
        "cleanup_failure_count",
        "no_repo_owned_target_logs_reports_manifests_or_transcripts",
        "run_specific_staging_cleanup_attempted_on_all_failure_paths",
        "no_monitoring_bypass_or_log_suppression",
    ]
    for fragment in required:
        assert fragment in text, f"missing software install script fragment: {fragment}"

    forbidden = [
        "Clear-EventLog",
        "wevtutil cl",
        "Remove-EventLog",
        "New-Service",
        "Register-ScheduledTask",
        "Start-Transcript",
        "Stop-Transcript",
        "-Credential",
    ]
    for fragment in forbidden:
        assert fragment not in text, f"forbidden software install script fragment present: {fragment}"

    assert "if (-not $WhatIfPreference -and -not (Test-Path -LiteralPath $installerPath" in text


def test_schema_keeps_requests_bounded():
    schema = load_json(SCHEMA)
    assert schema["title"] == "SysAdminSuite software install request"
    assert schema["properties"]["software_share_root"]["default"] == "\\\\nt2kwb972sms01\\"
    assert schema["properties"]["targets"]["maxItems"] == 25
    assert "allow_target_mutation" in schema["required"]
    assert schema["properties"]["allow_target_mutation"]["const"] is True
    assert schema["properties"]["install_mode"]["enum"] == ["UncDirect", "CopyThenInstall"]


def test_contract_is_wired_into_offline_runner_and_precommit():
    runner = read(RUNNER)
    pre_commit = read(PRE_COMMIT)
    assert "python3 Tests/survey/test_software_install_harness_contracts.py" in runner
    assert "python3 Tests/survey/test_software_install_harness_contracts.py" in pre_commit


def test_behavioral_pester_covers_dry_run_and_cleanup_failures():
    text = read(PESTER)
    for fragment in [
        "rejects an arbitrary UNC root before contacting it",
        "keeps WhatIf local and does not probe the share or target",
        "cleans run-specific staging after a copy failure",
        "preserves the original failure and reports cleanup uncertainty",
        "Should -Invoke New-PSSession -Times 0 -Exactly",
        "Should -Invoke Invoke-Command -Times 2 -Exactly",
    ]:
        assert fragment in text, f"missing behavioral Pester fragment: {fragment}"


if __name__ == "__main__":
    test_api_manifest_declares_gated_operator_execute_surface()
    test_document_names_no_artifact_boundary_without_stealth_claims()
    test_script_enforces_approved_source_and_explicit_mutation_gate()
    test_schema_keeps_requests_bounded()
    test_contract_is_wired_into_offline_runner_and_precommit()
    test_behavioral_pester_covers_dry_run_and_cleanup_failures()
