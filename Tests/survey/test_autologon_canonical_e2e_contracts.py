#!/usr/bin/env python3
"""Dependency-free contracts for the composed AutoLogon fixture E2E lane."""
from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MATRIX = ROOT / "Tests" / "Fixtures" / "autologon-canonical-e2e" / "scenarios.json"
RESULT_SCHEMA = ROOT / "schemas" / "harness" / "autologon-canonical-e2e-result.schema.json"
PROFILES = ROOT / "harness" / "e2e" / "e2e-profiles.json"
RUNNER = ROOT / "scripts" / "Invoke-SasAutoLogonE2E.ps1"
APPLICATION = ROOT / "scripts" / "Invoke-SasAutoLogonDeployment.ps1"
ADAPTER = ROOT / "scripts" / "SasSoftwareDeploymentAdapter.psm1"
VALIDATED_DEPLOYMENT = ROOT / "scripts" / "Invoke-SasValidatedSoftwareDeployment.ps1"
LEGACY_PLANNER = ROOT / "scripts" / "Invoke-SasSoftwareInstall.ps1"
VALIDATOR = ROOT / "tools" / "validate_autologon_e2e_artifacts.py"
PESTER = ROOT / "Tests" / "Pester" / "AutoLogonCanonicalE2E.Tests.ps1"
WORKFLOW = ROOT / ".github" / "workflows" / "autologon-canonical-e2e.yml"
OFFLINE = ROOT / "tests" / "survey" / "run_offline_survey_tests.sh"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def load(path: Path) -> dict:
    return json.loads(read(path))


def test_matrix_is_closed_complete_and_zero_network() -> None:
    matrix = load(MATRIX)
    assert matrix["schema_version"] == "sas-autologon-canonical-e2e-scenarios/v1"
    assert matrix["proof_class"] == "composed-sanitized-fixture-e2e"
    assert matrix["network_scope"] == "none"
    assert matrix["live_target_mutation"] is False
    expected = {
        "canonical_success": "fixture_pass",
        "transport_rejection": "transport_rejected",
        "hash_mismatch": "hash_mismatch",
        "baseline_failure": "baseline_failed",
        "already_configured": "already_configured",
        "installer_failure": "installer_failed",
        "validation_failure": "validation_failed",
        "cleanup_failure": "cleanup_failed",
        "state_mismatch": "state_mismatch",
        "missing_authorization": "authorization_rejected",
        "missing_password_presence": "password_presence_missing",
        "missing_before_evidence": "final_gate_before_missing",
        "disabled_catalog": "final_gate_catalog_disabled",
    }
    scenarios = {item["id"]: item for item in matrix["scenarios"]}
    assert len(matrix["scenarios"]) == len(scenarios) == 13
    assert {key: value["expected_classification"] for key, value in scenarios.items()} == expected
    assert all(re.fullmatch(r"[a-z][a-z0-9_]{2,95}", item["expected_reason_code"]) for item in scenarios.values())


def test_profile_is_dedicated_and_not_silently_defaulted() -> None:
    catalog = load(PROFILES)
    journeys = {item["id"]: item for item in catalog["journeys"]}
    profiles = {item["id"]: item for item in catalog["profiles"]}
    assert catalog["default_profile"] == "default"
    assert "autologon-canonical-fixture-e2e" not in profiles["default"]["journey_ids"]
    assert profiles["autologon"] == {
        "id": "autologon",
        "proof_class": "fixture-loopback-e2e",
        "journey_ids": ["autologon-canonical-fixture-e2e"],
    }
    journey = journeys["autologon-canonical-fixture-e2e"]
    assert journey["runtime_candidates"][0] == "powershell.exe"
    assert journey["script"] == "scripts/Invoke-SasAutoLogonE2E.ps1"
    assert journey["arguments"] == ["-OutputRoot", "{journey_output}"]
    assert journey["network_scope"] == "none"
    assert journey["target_mutation"] is False
    assert journey["required"] is True


def test_result_schema_is_closed_and_fixture_capped() -> None:
    schema = load(RESULT_SCHEMA)
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["additionalProperties"] is False
    assert schema["properties"]["schema_version"]["const"] == "sas-autologon-canonical-e2e-result/v1"
    safety = schema["properties"]["safety"]["properties"]
    assert all(item.get("const") is False for item in safety.values())
    execution = schema["properties"]["fixture_execution"]["properties"]
    assert execution["system_execution_is_simulated"]["const"] is True
    assert execution["simulated_execution_identity_sid"]["const"] == "S-1-5-18"
    receipt = schema["properties"]["receipt"]["properties"]
    assert receipt["classification"]["const"] == "contract_only"
    assert receipt["live_proof_promoted"]["const"] is False


def test_runner_crosses_real_composition_without_live_authority() -> None:
    runner = read(RUNNER)
    application = read(APPLICATION)
    adapter = read(ADAPTER)
    validated_deployment = read(VALIDATED_DEPLOYMENT)
    legacy_planner = read(LEGACY_PLANNER)
    required = (
        "Build-SasSoftwareInstallFixtureExecutable.ps1",
        "Invoke-SasAutoLogonDeployment.ps1",
        "Invoke-SasAutoLogonFinalStepGate.ps1",
        "requires_validated_installer_arguments=$false",
        "installer_arguments_policy='approved_empty'",
        "installer_arguments_reference='sanitized fixture no-argument record'",
        "$approvedEmptyRequestVerified",
        "@($closedRequest.installer_arguments).Count -eq 0",
        "Invoke-SasSmbScheduledTaskDeploymentFixture",
        "generated_installer_executed",
        "pinned_source_hash_verified",
        "staged_hash_verified",
        "simulated_execution_identity_sid='S-1-5-18'",
        "system_execution_is_simulated=$true",
        "zero_run_scoped_remnants_verified",
        "default_password_value_read=$false",
        "source_evidence_copied=$false",
        "live_proof_promoted=$false",
        "validate_autologon_e2e_artifacts.py",
        "[AllowEmptyCollection()][Collections.Generic.List[object]]$List",
        "scenarios=$scenarioRows.ToArray()",
        "artifacts=$validationArtifacts.ToArray()",
        "failed_gate_ids=",
        "cleanup_failures=",
        'E2E_FAILURE|{0}',
        "$localFixtureCleanupVerified = $false\ntry {",
        "finally {\n    # Remove both the harmless installed state",
        "foreach ($fixtureCleanupRoot in @($fixtureTarget,$generatedRoot))",
        "Remove-Item -LiteralPath $fixtureCleanupRoot -Recurse -Force -ErrorAction Stop",
        "$adapterCleanupVerified = ([bool]$adapter.cleanup.attempted -and",
        "$composedCleanupVerified = ($adapterCleanupVerified -and $localFixtureCleanupVerified)",
        "$composedZeroRemnantsVerified = ($zeroRunScopedRemnants -and $localFixtureCleanupVerified)",
    )
    for marker in required:
        assert marker in runner, marker
    assert "scenarios=@($scenarioRows)" not in runner
    assert "artifacts=@($validationArtifacts)" not in runner
    assert "Write-Error $failure" not in runner
    assert '$matrixLines.Add(("E2E_FAILURE|{0}"' in runner
    for scenario in (
        "baseline_failure",
        "installer_failure",
        "state_mismatch",
        "missing_password_presence",
    ):
        assert f"'{scenario}'" in application
    assert "'installer_failure'" in adapter
    assert "if ($AllowFixtures -and $WhatIfPreference)" in validated_deployment
    assert "Normalize-UncRoot '\\\\fixture.invalid\\'" in validated_deployment
    assert "$installParameters.AllowFixtures = $true" in validated_deployment
    assert "if ($AllowFixtures -and -not $WhatIfPreference)" in legacy_planner
    assert "Normalize-SasUncRoot -Path '\\\\fixture.invalid\\'" in legacy_planner
    for forbidden in (
        r"Test-NetConnection",
        r"Resolve-DnsName",
        r"Invoke-WebRequest",
        r"Invoke-Command\s+-ComputerName",
        r"Register-ScheduledTask",
        r"New-ScheduledTask",
        r"Restart-Computer",
    ):
        assert not re.search(forbidden, runner, re.IGNORECASE), forbidden


def test_password_presence_failure_never_reads_or_emits_the_value() -> None:
    runner = read(RUNNER)
    application = read(APPLICATION)
    combined = runner + "\n" + application
    forbidden = (
        "Get-ItemPropertyValue",
        "ConvertTo-SecureString",
        "Get-Credential",
        "secret_value_emitted=$true",
        "default_password_value_collected = $true",
    )
    for marker in forbidden:
        assert marker.lower() not in combined.lower(), marker
    assert "default_password_present" in runner
    assert "default_password_value_collected" in runner


def test_validator_workflow_pester_and_offline_registration() -> None:
    validator = read(VALIDATOR)
    workflow = read(WORKFLOW)
    pester = read(PESTER)
    offline = read(OFFLINE)
    for schema in (
        "autologon-deployment-result.schema.json",
        "autologon-final-step-gate-result.schema.json",
        "autologon-state-proof-result.schema.json",
        "autologon-proof-source-evidence.schema.json",
        "autologon-proof-receipt.schema.json",
        "autologon-canonical-e2e-result.schema.json",
    ):
        assert schema in validator
    assert "fixture receipt promoted beyond contract_only" in validator
    assert "windows-latest" in workflow
    assert "shell: powershell" in workflow
    assert "Invoke-SasEndToEndValidation.ps1" in workflow
    assert "-Profile autologon" in workflow
    assert "AutoLogonCanonicalDeployment.Tests.ps1" in workflow
    assert "AutoLogonCanonicalE2E.Tests.ps1" in workflow
    assert "if-no-files-found: error" in workflow
    assert "raw-fixture-evidence" not in workflow
    assert "Invoke-SasAutoLogonE2E.ps1" in pester
    assert "test_autologon_canonical_e2e_contracts.py" in offline


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_") and callable(value)]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} canonical AutoLogon E2E contracts")


if __name__ == "__main__":
    main()
