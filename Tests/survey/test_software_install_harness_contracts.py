#!/usr/bin/env python3
"""Static contracts for the SysAdminSuite approved software install harness."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
API = ROOT / "harness" / "api" / "sas-harness-api.json"
DOC = ROOT / "docs" / "SOFTWARE_INSTALL_HARNESS.md"
SCRIPT = ROOT / "scripts" / "Invoke-SasSoftwareInstall.ps1"
SCHEMA = ROOT / "schemas" / "harness" / "software-install-request.schema.json"
RUNNER = ROOT / "tests" / "survey" / "run_offline_survey_tests.sh"
PRE_COMMIT = ROOT / ".githooks" / "pre-commit"


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
        "Prefer_UNC_direct_install_to_avoid_target_staging",
        "Temporary_staging_must_be_removed_and_cleanup_status_reported",
        "Local_gitignored_evidence_only",
    }
    assert required_guardrails <= set(op["guardrails"])


def test_document_names_no_artifact_boundary_without_stealth_claims():
    text = read(DOC)
    required = [
        "not stealth tooling",
        "must not suppress Windows logs",
        "no persistent SysAdminSuite staging payloads",
        "\\\\nt2kwb972sms01\\",
        "UncDirect",
        "CopyThenInstall",
        "Cleanup failure is a reportable failure",
        "Generated run artifacts stay in gitignored local output paths",
    ]
    for fragment in required:
        assert fragment in text, f"missing software install doc fragment: {fragment}"


def test_script_enforces_approved_source_and_explicit_mutation_gate():
    text = read(SCRIPT)
    required = [
        "[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]",
        "\\\\nt2kwb972sms01\\",
        "Resolve-SasApprovedInstallerPath",
        "InstallerRelativePath must be relative",
        "parent-directory traversal",
        "-AllowTargetMutation",
        "Refusing target mutation without -AllowTargetMutation",
        "No targets were supplied",
        "exceeds MaxTargets",
        "New-PSSession -ComputerName $target",
        "Copy-Item -LiteralPath $installerPath -Destination $remoteInstallerPath -ToSession $session -Force",
        "Remove-Item -LiteralPath $stageRoot -Recurse -Force",
        "cleanup_failure_count",
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
        "-Credential",
    ]
    for fragment in forbidden:
        assert fragment not in text, f"forbidden software install script fragment present: {fragment}"


def test_schema_keeps_requests_bounded():
    schema = load_json(SCHEMA)
    assert schema["title"] == "SysAdminSuite software install request"
    assert schema["properties"]["software_share_root"]["default"] == "\\\\nt2kwb972sms01\\"
    assert schema["properties"]["targets"]["maxItems"] == 25
    assert schema["properties"]["allow_target_mutation"]["const"] is True
    assert schema["properties"]["install_mode"]["enum"] == ["UncDirect", "CopyThenInstall"]


def test_contract_is_wired_into_offline_runner_and_precommit():
    runner = read(RUNNER)
    pre_commit = read(PRE_COMMIT)
    assert "python3 Tests/survey/test_software_install_harness_contracts.py" in runner
    assert "python3 Tests/survey/test_software_install_harness_contracts.py" in pre_commit


if __name__ == "__main__":
    test_api_manifest_declares_gated_operator_execute_surface()
    test_document_names_no_artifact_boundary_without_stealth_claims()
    test_script_enforces_approved_source_and_explicit_mutation_gate()
    test_schema_keeps_requests_bounded()
    test_contract_is_wired_into_offline_runner_and_precommit()
