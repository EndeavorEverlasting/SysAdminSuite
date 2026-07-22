#!/usr/bin/env python3
"""Dependency-free contracts for the harmless SMB transport live-cert producer."""
from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "scripts" / "SasSoftwareDeploymentLiveCert.psm1"
ENTRYPOINT = ROOT / "scripts" / "Invoke-SasSoftwareDeploymentTransportLiveCert.ps1"
PESTER = ROOT / "Tests" / "Pester" / "SoftwareDeploymentTransportLiveCert.Tests.ps1"
SCENARIOS = ROOT / "Tests" / "Fixtures" / "software-deployment-transport-live-cert" / "scenarios.json"
SOURCE_SCHEMA = ROOT / "schemas" / "harness" / "software-deployment-transport-live-cert-result.schema.json"
SOURCE_FIXTURE = ROOT / "Tests" / "Fixtures" / "software-deployment-transport" / "live-cert-result.fixture.json"
WORKFLOW = ROOT / "harness" / "workflows" / "software-deployment-transport.yaml"
API = ROOT / "harness" / "api" / "sas-harness-api.json"
CI = ROOT / ".github" / "workflows" / "harness-contracts.yml"
OFFLINE = ROOT / "tests" / "survey" / "run_offline_survey_tests.sh"
DOC = ROOT / "docs" / "SOFTWARE_DEPLOYMENT_TRANSPORT_CONTRACT.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def test_repository_owned_surfaces_are_present() -> None:
    for path in (MODULE, ENTRYPOINT, PESTER, SCENARIOS, SOURCE_SCHEMA, SOURCE_FIXTURE, WORKFLOW, API, CI, OFFLINE, DOC):
        assert path.is_file(), path


def test_entrypoint_is_one_target_and_separately_mutation_gated() -> None:
    text = read(ENTRYPOINT)
    for marker in (
        "[CmdletBinding(DefaultParameterSetName = 'Live')]",
        "[string]$ComputerName",
        "[string]$PreflightResultPath",
        "[switch]$AllowNetworkActivity",
        "[switch]$AllowTargetMutation",
        "Read-SasDeploymentTransportPreflight",
        "kerberos_smb_task_ready",
        "operator_local_live",
        "sanitized_fixture",
        "Invoke-SasSoftwareDeploymentTransportLiveCert",
        "operator_local_transport_live_cert_result.json",
    ):
        assert marker in text, marker
    parameter_region = text.split("param(", 1)[1].split("\n)\n", 1)[0]
    for forbidden in (
        "Credential", "Password", "Username", "InstallerPath", "PackagePath",
        "PackageName", "ArgumentList", "ScriptBlock", "TransportIntent",
    ):
        assert forbidden not in parameter_region, forbidden
    assert "selected_transport -ne 'kerberos_smb_task'" in text
    assert "Live certification cannot consume sanitized fixture" in text


def test_live_module_is_harmless_nonce_bound_and_has_no_fallback() -> None:
    text = read(MODULE)
    for marker in (
        r"C:\ProgramData\SysAdminSuite\TransportLiveCert\$RunId",
        "SysAdminSuite-TransportLiveCert-",
        "Invoke-HarmlessTransportCert.ps1",
        "S-1-5-18",
        "'/RU','SYSTEM'",
        "'/SC','ONCE'",
        "-NonInteractive",
        "Test-SasLiveCertWorkerResult",
        "nonce_verified",
        "retrieved_before_teardown",
        "verified_before_task_creation",
        "Get-FileHash -LiteralPath $remoteWorkerUnc",
        "software_installation_performed = $false",
        "harmless_payload_only = $true",
        "fallback_attempted = $false",
    ):
        assert marker in text, marker
    for forbidden in (
        "Start-Process", "msiexec", "InstallerArguments", "InstallerPath",
        "PackageName", "Get-Credential", "ConvertFrom-SecureString",
        "ConvertTo-SecureString", "Invoke-Expression", "DownloadFile",
        "Restart-Computer", "shutdown.exe",
    ):
        assert forbidden.lower() not in text.lower(), forbidden


def test_result_is_retrieved_before_task_and_staging_teardown() -> None:
    text = read(MODULE)
    live = text.split("function Invoke-SasSoftwareDeploymentTransportLiveCert {", 1)[1]
    live = live.split("function Invoke-SasSoftwareDeploymentTransportLiveCertFixture {", 1)[0]
    retrieve = live.index("Copy-Item -LiteralPath $remoteResultUnc -Destination $localResult")
    end_task = live.index("Invoke-SasLiveCertSchtasks -Arguments @('/End'")
    delete_task = live.index("Invoke-SasLiveCertSchtasks -Arguments @('/Delete'")
    delete_staging = live.index("Remove-Item -LiteralPath $remoteUncRoot -Recurse -Force")
    assert retrieve < end_task < delete_task < delete_staging
    assert "Invoke-SasLiveCertSchtasks -Arguments @('/Query'" in live
    assert "ended_or_not_running" in live
    assert "zero_remnants_verified" in live


def test_fixture_matrix_covers_success_execution_and_teardown_failures() -> None:
    payload = json.loads(read(SCENARIOS))
    scenarios = {item["id"]: item for item in payload["scenarios"]}
    assert set(scenarios) == {
        "success", "worker_hash_mismatch", "task_creation_failure", "task_run_failure", "result_timeout",
        "malformed_result", "not_system", "wrong_nonce", "task_deletion_failure",
        "staging_deletion_failure",
    }
    assert scenarios["success"]["expected_status"] == "certified"
    assert scenarios["success"]["expected_zero_remnants"] is True
    assert scenarios["task_deletion_failure"]["expected_status"] == "teardown_failed"
    assert scenarios["staging_deletion_failure"]["expected_status"] == "teardown_failed"
    pester = read(PESTER)
    assert "simulates the complete bounded fixture matrix" in pester
    assert "network_activity_performed | Should -BeFalse" in pester
    assert "target_mutation_performed | Should -BeFalse" in pester


def test_source_result_matches_the_closed_frozen_schema() -> None:
    schema = json.loads(read(SOURCE_SCHEMA))
    fixture = json.loads(read(SOURCE_FIXTURE))
    assert schema["additionalProperties"] is False
    assert schema["properties"]["schema_version"]["const"] == "sas-software-deployment-transport-live-cert-result/v1"
    assert fixture["privacy"] == {name: False for name in schema["properties"]["privacy"]["required"]}
    cert = schema["properties"]["certification"]["properties"]
    assert cert["software_installation_performed"]["const"] is False
    assert cert["harmless_payload_only"]["const"] is True
    module = read(MODULE)
    for field in schema["required"]:
        assert re.search(rf"\b{re.escape(field)}\s*=", module), field

    try:
        import jsonschema  # type: ignore
    except ImportError:
        return
    jsonschema.Draft202012Validator(schema).validate(fixture)


def test_workflow_ci_offline_runner_and_docs_are_wired() -> None:
    workflow = read(WORKFLOW)
    for marker in (
        "implementation_status: implemented_harmless_smb_live_cert",
        "application_entrypoint: scripts/Invoke-SasSoftwareDeploymentTransportLiveCert.ps1",
        "scripts/SasSoftwareDeploymentLiveCert.psm1",
        "harmless run-scoped certification task only",
    ):
        assert marker in workflow, marker
    test_path = "Tests/survey/test_software_deployment_transport_live_cert_contracts.py"
    assert test_path in read(CI)
    assert f"python3 {test_path}" in read(OFFLINE)
    assert "SoftwareDeploymentTransportLiveCert.Tests.ps1" in read(CI)
    operations = {item["id"]: item for item in json.loads(read(API))["operations"]}
    operation = operations["software_install.transport_live_cert"]
    assert {"allow_network_activity", "allow_target_mutation"} <= set(operation["inputs"])
    assert {"operator_local_transport_live_cert_result.json", "private_lifecycle_result.json", "english_summary.txt"} <= set(operation["outputs"])
    assert "Staged_worker_SHA256_verified_before_task_creation" in operation["guardrails"]
    doc = read(DOC)
    assert "Invoke-SasSoftwareDeploymentTransportLiveCert.ps1" in doc
    assert r"C:\ProgramData\SysAdminSuite\TransportLiveCert\<run_id>" in doc
    assert "live_cert_pass" in doc
    assert "live_transport_execution_and_cleanup" in doc
    for ceiling in ("software installation", "WinRM certification", "fleet readiness", "application acceptance"):
        assert ceiling in doc


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_") and callable(value)]
    for test in tests:
        test()
        print(f"PASS: {test.__name__}")
    print(f"PASS: {len(tests)} harmless transport live-cert contract groups")
