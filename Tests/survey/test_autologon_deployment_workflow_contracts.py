#!/usr/bin/env python3
"""Static contracts for the canonical AutoLogon deployment application path."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Invoke-SasAutoLogonDeployment.ps1"
SCENARIOS = ROOT / "Tests" / "Fixtures" / "autologon-canonical-transport" / "scenarios.json"
PESTER = ROOT / "Tests" / "Pester" / "AutoLogonCanonicalDeployment.Tests.ps1"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def test_authority_moves_to_canonical_front_door() -> None:
    content = read(SCRIPT)
    required = (
        "Invoke-SasValidatedSoftwareDeployment.ps1",
        "SasSoftwareDeploymentAdapter.psm1",
        "Resolve-SasSoftwareDeploymentTransport",
        "Invoke-SasSmbScheduledTaskDeploymentFixture",
        "Invoke-SasAutoLogonFinalStepGate.ps1",
        "Invoke-SasAutoLogonStateDelta.ps1",
        "SasRunContext.psm1",
    )
    for marker in required:
        assert marker in content, f"missing canonical authority marker: {marker}"
    assert "$softwareInstallScript" not in content
    assert "Join-Path $PSScriptRoot 'Invoke-SasSoftwareInstall.ps1'" not in content


def test_closed_request_requires_identity_hash_arguments_authorization_and_cleanup() -> None:
    content = read(SCRIPT)
    required = (
        "[ValidateSet('autologon')]",
        "$InstallerSha256",
        "$InstallerArgumentsReference",
        "$AuthorizedBy",
        "$RequestReference",
        "$ChangeReference",
        "$TicketReference",
        "$RequireValidSignature",
        "$ExpectedSignerThumbprint",
        "sas-validated-software-deployment-request/v1",
        "Test-SasValidatedDeploymentRequest",
        "repo_owned_run_scoped_only",
        "RegistryValueEquals",
        "SetAutoLogon",
        "AutoAdminLogon",
    )
    for marker in required:
        assert marker in content, f"missing closed request contract: {marker}"
    assert "A pinned 64-character -InstallerSha256 is required" in content
    assert "Explicit vendor-validated -InstallerArguments are required" in content


def test_catalog_is_authoritative_without_committed_private_defaults() -> None:
    content = read(SCRIPT)
    assert "sas-approved-software-catalog/v1" in content
    assert "source_folder_relative_path" in content
    assert "installer_file" in content
    assert "is not an approved software source for AutoLogon" in content
    assert "nt2kwb972sms01" not in content.lower()
    assert "packages\\AutoLogonSetup\\NW_AutoLogon_Setup_x64.exe" not in content


def test_preflight_and_gate_order_fail_closed() -> None:
    content = read(SCRIPT)
    preflight = "Resolve-SasSoftwareDeploymentTransport -Transport $Transport"
    before = "$before = & $stateDeltaScript"
    gate = "$gateResults += & $finalGateScript"
    live_loop = "for ($gateIndex = 0; $gateIndex -lt $gatePassedTargets.Count; $gateIndex++)"
    assert preflight in content and before in content and gate in content and live_loop in content
    assert content.index(preflight) < content.index(before) < content.index(gate) < content.index(live_loop)
    assert "final_gate_passed" in content
    assert "mutation_cancelled_before_canonical_front_door" in content
    assert "WinRM selection is not authorized" in content
    assert "Live canonical AutoLogon targets must be exact authorized FQDNs" in content
    assert "Transport preflight must remain under survey/input or survey/output" in content
    assert "Sort-Object -Unique" not in content


def test_baseline_reduction_and_package_preservation_are_retained() -> None:
    content = read(SCRIPT)
    for marker in (
        "ELIGIBLE_FOR_INSTALL",
        "SKIP_BASELINE_COLLECTION_FAILED",
        "SKIP_ALREADY_CONFIGURED",
        "already_configured_skipped",
        "cleanup_verified",
        "zero_remnants_verified",
        "repo_artifact_remaining",
        "run_scoped_teardown_failed",
    ):
        assert marker in content, f"missing reduction/finalization contract: {marker}"
    assert "requested_software_uninstall" not in content
    assert "fallback" not in content.lower() or "no direct AutoLogon authority" in content


def test_p09_results_and_artifacts_are_emitted() -> None:
    content = read(SCRIPT)
    required = (
        "sas-autologon-deployment-result/v1",
        "autologon.admin_deploy",
        "autologon_deployment_result.json",
        "sas-autologon-final-step-gate-result/v1",
        "autologon_final_step_gate_result.json",
        "sas-autologon-state-proof-result/v1",
        "autologon_state_proof_result.json",
        "Register-SasArtifact",
        "artifact_registry_path",
        "canonical_front_door_used",
        "sanitized_fixture_contract",
    )
    for marker in required:
        assert marker in content, f"missing P09 emission contract: {marker}"
    assert content.count("fixture_adapter_result_count") >= 3, "every terminal summary path must emit the fixture adapter count"


def test_fixture_mode_stays_non_runtime_and_uses_synthetic_fqdn() -> None:
    content = read(SCRIPT)
    assert "fixture-$($index + 1).autologon.invalid" in content
    assert "FixtureMode is offline and cannot be combined with -AllowTargetMutation" in content
    assert "network_activity_performed = (-not $FixtureMode)" in content
    for field in (
        "task_created",
        "executed_as_system",
        "installer_executed",
        "result_retrieved",
        "cleanup_verified",
        "zero_remnants_verified",
    ):
        assert f"{field} = $(if ($FixtureMode) {{ $false }}" in content
    assert "automatic sign-in" in content
    assert "application behavior" in content


def test_fixture_matrix_is_closed_and_complete() -> None:
    fixture = json.loads(read(SCENARIOS))
    assert fixture["schema_version"] == "sas-autologon-canonical-fixture-matrix/v1"
    expected = {
        "ready": ("fixture_contract_pass", "fixture_canonical_path_validated"),
        "blocked": ("fixture_contract_failed", "final_step_gate_blocked"),
        "already_configured": ("fixture_contract_pass", "already_configured_skipped"),
        "hash_mismatch": ("fixture_contract_failed", "installer_hash_mismatch"),
        "transport_rejection": ("fixture_contract_failed", "transport_preflight_rejected"),
        "task_failure": ("fixture_contract_failed", "scheduled_task_execution_failed"),
        "validation_failure": ("fixture_contract_failed", "package_validation_failed"),
        "teardown_failure": ("fixture_contract_failed", "run_scoped_teardown_failed"),
    }
    scenarios = {item["id"]: item for item in fixture["scenarios"]}
    assert set(scenarios) == set(expected)
    for scenario_id, (classification, reason) in expected.items():
        item = scenarios[scenario_id]
        assert item["classification"] == classification
        assert item["reason_code"] == reason
        assert item["network_activity_performed"] is False
        assert item["target_mutation_performed"] is False
        assert item["live_runtime_proven"] is False

    content = read(SCRIPT)
    for adapter_scenario in ("source_hash_mismatch", "task_run_failure", "run_root_deletion_failure"):
        assert f"'{adapter_scenario}'" in content
    assert "Synthetic required package validation failed" in content


def test_fixture_matrix_has_executable_pester_coverage() -> None:
    content = read(PESTER)
    assert "Invoke-SasAutoLogonDeployment.ps1" in content
    assert "scenarios.json" in content
    assert "FixtureScenario" in content
    assert "deployment_result_json" in content
    assert "sas-autologon-deployment-result/v1" in content


def test_no_secret_value_or_persistence_authority_is_added() -> None:
    content = read(SCRIPT)
    forbidden = (
        "Get-ItemPropertyValue -LiteralPath 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon' -Name 'DefaultPassword'",
        "ConvertTo-SecureString",
        "cmdkey",
        "Register-ScheduledTask",
        "New-ScheduledTask",
        "New-Service",
        "sc.exe create",
    )
    for marker in forbidden:
        assert marker.lower() not in content.lower(), f"forbidden secret/persistence authority: {marker}"
    assert "default_password_value_collected = $false" in content
    assert "secret_value_emitted = $false" in content


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_") and callable(value)]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} canonical AutoLogon deployment workflow contracts")


if __name__ == "__main__":
    main()
