#!/usr/bin/env python3
"""Dependency-free contracts for the canonical SMB/Task Scheduler adapter."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADAPTER = ROOT / "scripts" / "SasSoftwareDeploymentAdapter.psm1"
FRONT_DOOR = ROOT / "scripts" / "Invoke-SasValidatedSoftwareDeployment.ps1"
BASH = ROOT / "bash" / "apps" / "sas-install-apps.sh"
PESTER = ROOT / "Tests" / "Pester" / "SmbScheduledTaskDeployment.Tests.ps1"
SCHEMA = ROOT / "schemas" / "harness" / "smb-scheduled-task-deployment-result.schema.json"
SCENARIOS = ROOT / "Tests" / "Fixtures" / "smb-scheduled-task-deployment" / "scenarios.json"
OFFLINE = ROOT / "tests" / "survey" / "run_offline_survey_tests.sh"
DOC = ROOT / "docs" / "SMB_SCHEDULED_TASK_SOFTWARE_INSTALL.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def test_surfaces_and_closed_result_schema() -> None:
    for path in (ADAPTER, FRONT_DOOR, BASH, PESTER, SCHEMA, SCENARIOS, OFFLINE, DOC):
        assert path.is_file(), path
    schema = json.loads(read(SCHEMA))
    assert schema["additionalProperties"] is False
    assert schema["properties"]["transport"]["const"] == "SmbScheduledTask"
    assert schema["properties"]["fallback_attempted"]["const"] is False
    assert schema["properties"]["target"]["format"] == "hostname"
    assert schema["properties"]["status"]["enum"] == [
        "failed_before_staging", "staged_hash_verified", "task_started",
        "deployment_failed_pending_cleanup", "deployment_failed_cleaned",
        "cleanup_failed", "completed", "completed_reboot_required",
    ]


def test_selector_consumes_fresh_consistent_p02_without_fallback() -> None:
    text = read(ADAPTER)
    for fragment in (
        "Resolve-SasSoftwareDeploymentTransport",
        "Read-SasDeploymentTransportPreflight",
        "Transport preflight result is stale",
        "New-SasSoftwareDeploymentTransportResult",
        "Transport preflight result is inconsistent with its observations",
        "Auto transport requires a fresh schema-valid P02 result",
        "Explicit transport $Transport conflicts with the supplied P02 decision",
        "selected_before_mutation = $true",
        "silent_fallback_permitted = $false",
        "fallback_after_mutation_permitted = $false",
    ):
        assert fragment in text, fragment
    assert "Invoke-SasSoftwareDeploymentTransportObservation" not in text


def test_smb_adapter_pins_hashes_system_identity_and_complete_teardown() -> None:
    text = read(ADAPTER)
    for fragment in (
        "SmbScheduledTask requires the exact authorized FQDN",
        "\\\\$ComputerName\\ADMIN$",
        "\\\\$ComputerName\\C$",
        "C:\\ProgramData\\SysAdminSuite\\SoftwareInstall\\$RunId",
        "Source SHA-256 changed before SMB staging",
        "Target or transient worker SHA-256 mismatch before task creation",
        "Get-FileHash -LiteralPath $config.installer_path",
        "S-1-5-18",
        "'/RU','SYSTEM'",
        "'/SC','ONCE'",
        "result_retrieval",
        "Invoke-SasSchtasksCommand -Arguments @('/Delete'",
        "Invoke-SasSchtasksCommand -Arguments @('/Query'",
        "Remove-Item -LiteralPath $remoteUncRoot -Recurse -Force",
        "result.status = 'cleanup_failed'",
        "fallback_attempted = $false",
        "completed_reboot_required",
    ):
        assert fragment in text, fragment
    for forbidden in (
        "Get-Credential", "ConvertFrom-SecureString", "ConvertTo-SecureString",
        "Restart-Computer", "shutdown.exe", "Clear-EventLog", "wevtutil cl",
        "git clone", "Invoke-Expression",
    ):
        assert forbidden.lower() not in text.lower(), forbidden
    parameter_region = text.split("function Invoke-SasSmbScheduledTaskDeployment {", 1)[1].split(")\n\n    if", 1)[0]
    for forbidden_parameter in ("Credential", "Password", "SmbPass", "SmbUser", "Secret"):
        assert forbidden_parameter not in parameter_region
    assert text.count(
        "[Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$InstallerArguments"
    ) == 2
    assert "-InstallerArguments @()" in read(PESTER)


def test_front_door_keeps_winrm_optional_and_smb_first_class() -> None:
    text = read(FRONT_DOOR)
    for fragment in (
        "[ValidateSet('Auto', 'WinRM', 'SmbScheduledTask')]",
        "[string]$Transport = 'WinRM'",
        "TransportPreflightPath",
        "One validated deployment run cannot mix transports",
        "Invoke-SasSmbScheduledTaskDeployment",
        "Invoke-SasSoftwareInstall.ps1",
        "Invoke-SasSoftwareInstallFinalization.ps1",
        "transport_selected_before_mutation",
        "transport_fallback_attempted",
        "no_automatic_reboot",
    ):
        assert fragment in text, fragment
    assert text.index("$PSCmdlet.ShouldProcess") < text.index("$installerPath = Resolve-ValidatedInstallerPath")


def test_smb_finalization_is_closed_and_emits_reviewable_lifecycle() -> None:
    adapter = read(ADAPTER)
    front_door = read(FRONT_DOOR)
    pester = read(PESTER)
    for fragment in (
        "Resolve-SasSmbDeploymentFinalizationStatus",
        "VALIDATION_FAILED_TOOLS_REMOVED",
        "REQUESTED_SOFTWARE_NOT_PRESERVED_AFTER_TEARDOWN",
        "TEARDOWN_FAILED",
        "COMPLETED_VALIDATED_FINALIZED",
    ):
        assert fragment in adapter, fragment
    for event in (
        "'run_started'", "'target_started'", "'target_completed'",
        "'finalization_started'", "'target_finalization_completed'",
        "'finalization_completed'", "'run_completed'",
    ):
        assert event in front_door, event
    for fragment in (
        "validation_failure_count = $validationFailureCount",
        "preservation_failure_count = $preservationFailureCount",
        "Resolve-SasSmbDeploymentFinalizationStatus -Result $_",
    ):
        assert fragment in front_door, fragment
    assert "classifies success, validation, preservation, install, and teardown independently" in pester
    assert "runs the final evidence reviewer across SMB success and closed failure packages" in pester
    assert "MissingLifecycleEvent" in pester
    assert "-TimeoutSeconds 15" in read(DOC)


def test_failure_matrix_is_complete_and_pester_drives_it() -> None:
    fixture = json.loads(read(SCENARIOS))
    actual = {item["id"] for item in fixture["scenarios"]}
    expected = {
        "success", "source_hash_mismatch", "target_hash_mismatch", "admin_share_denied",
        "task_creation_failure", "task_run_failure", "installer_failure", "result_timeout", "malformed_result",
        "task_deletion_failure", "run_root_deletion_failure", "remaining_task", "remaining_file",
    }
    assert actual == expected
    pester = read(PESTER)
    for fragment in (
        "rejects a stale P02 result",
        "rejects an inconsistent P02 decision",
        "has no credential, password, user, or secret parameter surface",
        "simulates every bounded failure and success fixture",
        "fallback_attempted | Should -BeFalse",
    ):
        assert fragment in pester


def test_compatibility_wrapper_and_offline_wiring() -> None:
    bash = read(BASH)
    for fragment in (
        "--request PATH",
        "Invoke-SasValidatedSoftwareDeployment.ps1",
        "--transport VALUE",
        "--transport-preflight PATH",
        "compatibility mode",
    ):
        assert fragment in bash, fragment
    assert "python3 Tests/survey/test_canonical_smb_task_deployment_contracts.py" in read(OFFLINE)


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_") and callable(value)]
    for test in tests:
        test()
        print(f"PASS: {test.__name__}")
    print(f"PASS: {len(tests)} canonical SMB scheduled-task deployment contracts")
