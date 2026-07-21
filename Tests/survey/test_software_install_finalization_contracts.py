#!/usr/bin/env python3
"""Dependency-free contracts for validated install, teardown, and preservation."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / "schemas/harness/validated-software-deployment-request.schema.json"
MODULE = ROOT / "scripts/SasSoftwareInstallFinalization.psm1"
FINALIZER = ROOT / "scripts/Invoke-SasSoftwareInstallFinalization.ps1"
ORCHESTRATOR = ROOT / "scripts/Invoke-SasValidatedSoftwareDeployment.ps1"
INSPECTOR = ROOT / "scripts/Show-SasValidatedSoftwareDeploymentResult.ps1"
CMD = ROOT / "Inspect-LatestValidatedSoftwareDeployment.cmd"
E2E = ROOT / "scripts/Invoke-SasValidatedSoftwareDeploymentE2E.ps1"
DOC = ROOT / "docs/SOFTWARE_INSTALL_VALIDATED_FINALIZATION.md"
EXAMPLE = ROOT / "docs/examples/validated-deployment-request.example.json"
PROFILE = ROOT / "harness/e2e/e2e-profiles.json"
WORKFLOW = ROOT / ".github/workflows/default-e2e-validation.yml"
OFFLINE = ROOT / "tests/survey/run_offline_survey_tests.sh"
PESTER_REQUEST = ROOT / "Tests/Pester/ValidatedSoftwareDeploymentRequest.Tests.ps1"


def read(path: Path) -> str:
    assert path.exists(), f"missing finalization surface: {path}"
    return path.read_text(encoding="utf-8")


def test_surfaces_exist_and_json_parses() -> None:
    for path in (
        SCHEMA,
        MODULE,
        FINALIZER,
        ORCHESTRATOR,
        INSPECTOR,
        CMD,
        E2E,
        DOC,
        EXAMPLE,
        PROFILE,
        WORKFLOW,
        OFFLINE,
        PESTER_REQUEST,
    ):
        assert path.exists(), f"missing finalization surface: {path}"
    schema = json.loads(read(SCHEMA))
    assert schema["additionalProperties"] is False
    assert schema["properties"]["schema_version"]["const"] == "sas-validated-software-deployment-request/v1"
    assert schema["properties"]["cleanup_policy"]["const"] == "repo_owned_run_scoped_only"
    assert schema["allOf"][0]["then"]["required"] == ["expected_signer_thumbprint"]
    example = json.loads(read(EXAMPLE))
    try:
        import jsonschema
    except ImportError:
        jsonschema = None
    if jsonschema is not None:
        jsonschema.Draft202012Validator.check_schema(schema)
        jsonschema.validate(example, schema)


def test_request_contract_is_pinned_authorized_and_bounded() -> None:
    schema = json.loads(read(SCHEMA))
    required = set(schema["required"])
    assert {"installer_sha256", "installer_arguments_reference", "authorization", "validation", "cleanup_policy"}.issubset(required)
    assert schema["properties"]["targets"]["maxItems"] == 25
    assert schema["properties"]["validation"]["properties"]["checks"]["maxItems"] == 16
    check_types = set(schema["$defs"]["baseCheck"]["properties"]["type"]["enum"])
    assert check_types == {
        "FileExists", "FileSha256Equals", "FileVersionEquals", "JsonPropertyEquals",
        "RegistryValueEquals", "UninstallEntry", "ServiceExists",
    }


def test_runtime_validator_enforces_closed_schema_guardrails() -> None:
    module = read(MODULE)
    for fragment in (
        "REQUEST_FIELD_UNKNOWN",
        "AUTHORIZATION_FIELD_UNKNOWN",
        "VALIDATION_FIELD_UNKNOWN",
        "VALIDATION_CHECK_FIELD_UNKNOWN",
        "INSTALLER_ARGUMENTS_NOT_ARRAY",
        "TARGETS_NOT_ARRAY",
        "TARGET_DUPLICATE",
        "REQUIRE_VALID_SIGNATURE_TYPE_INVALID",
        "EXPECTED_SIGNER_THUMBPRINT_INVALID",
        "VALIDATION_SERVICE_STATUS_INVALID",
        "Select-Object -Unique",
    ):
        assert fragment in module, f"runtime request validator is missing: {fragment}"

    pester = read(PESTER_REQUEST)
    for fragment in (
        "accepts the tracked schema-valid example",
        "rejects unknown root properties",
        "rejects scalar target input and case-insensitive duplicate targets",
        "requires an actual boolean for signature enforcement",
        "rejects unknown validation-check properties",
        "rejects unsupported service states before target execution",
    ):
        assert fragment in pester, f"missing executable request rejection proof: {fragment}"
    for forbidden in ("Invoke-Command", "Start-Process", "New-PSSession", "AllowTargetMutation"):
        assert forbidden not in pester, f"offline request tests must not cross mutation boundary: {forbidden}"


def test_no_arbitrary_validation_or_broad_cleanup() -> None:
    text = read(MODULE) + "\n" + read(FINALIZER) + "\n" + read(ORCHESTRATOR)
    winrm_finalization_text = read(MODULE) + "\n" + read(FINALIZER)
    for required in (
        "VALIDATION_REGISTRY_VALUE_NAME_FORBIDDEN",
        "repo_owned_run_scoped_only",
        "SysAdminSuite\\SoftwareInstall\\{0}",
        "REQUESTED_SOFTWARE_NOT_PRESERVED_AFTER_TEARDOWN",
        "COMPLETED_VALIDATED_FINALIZED",
        "requested_software_uninstall_performed = $false",
        "Get-AuthenticodeSignature",
        "Installer SHA-256 mismatch",
    ):
        assert required in text, f"missing guardrail or finalization contract: {required}"
    for forbidden in (
        "Invoke-Expression",
        "EncodedCommand",
        "Win32_Product",
        "Clear-EventLog",
        "wevtutil cl",
        "Remove-Item -Path $env:ProgramData -Recurse",
        "New-Service",
    ):
        assert forbidden.lower() not in text.lower(), f"forbidden broad behavior present: {forbidden}"
    assert "scheduledtask" not in winrm_finalization_text.lower(), "WinRM finalization must not create scheduled tasks"


def test_cleanup_runs_after_validation_and_preservation_is_rechecked() -> None:
    text = read(FINALIZER)
    before = text.index("$validationBefore = Invoke-Command")
    cleanup = text.index("$cleanup = Invoke-Command")
    after = text.index("$validationAfter = Invoke-Command")
    assert before < cleanup < after
    assert "Cleanup runs even when installation or validation failed" in text
    assert "requested_software_preserved_after_teardown" in text


def test_finalizer_and_orchestrator_both_fail_closed_on_mutation() -> None:
    finalizer = read(FINALIZER)
    orchestrator = read(ORCHESTRATOR)
    assert "SupportsShouldProcess = $true" in finalizer
    assert "Refusing software-install finalization without -AllowTargetMutation" in finalizer
    assert "$PSCmdlet.ShouldProcess" in finalizer
    assert "[switch]$AllowTargetMutation" in finalizer
    assert "-AllowTargetMutation `" in orchestrator
    assert "-Confirm:$false" in orchestrator
    assert "SupportsShouldProcess = $true" in orchestrator
    assert "if (-not $WhatIfPreference -and -not $PSCmdlet.ShouldProcess" in orchestrator
    confirmation_gate = orchestrator.index("$PSCmdlet.ShouldProcess")
    package_contact = orchestrator.index("$installerPath = Resolve-ValidatedInstallerPath")
    target_mutation = orchestrator.index("& $installerScript")
    assert confirmation_gate < package_contact < target_mutation


def test_orchestrator_is_canonical_and_live_fails_closed() -> None:
    text = read(ORCHESTRATOR)
    for fragment in (
        "Refusing validated deployment without -AllowTargetMutation",
        "Invoke-SasSoftwareInstall.ps1",
        "Invoke-SasSoftwareInstallFinalization.ps1",
        "Get-FileHash",
        "Get-AuthenticodeSignature",
        "PLAN_ONLY_NO_INSTALL",
        "Validated deployment did not complete",
    ):
        assert fragment in text
    assert text.index("Get-FileHash") < text.index("& $installerScript") < text.index("& $finalizerScript")


def test_inspector_only_accepts_full_validated_finalization() -> None:
    text = read(INSPECTOR)
    for classification in (
        "DEPLOYMENT_COMPLETE_VALIDATED_AND_FINALIZED",
        "INSTALL_FAILED_TOOLS_REMOVED",
        "POST_INSTALL_VALIDATION_FAILED_TOOLS_REMOVED",
        "TEARDOWN_FAILED",
        "REQUESTED_SOFTWARE_NOT_PRESERVED",
        "EVIDENCE_INVALID",
    ):
        assert classification in text
    assert "installer_hash_verified" in text
    assert "requested_software_uninstall_performed" in text
    assert "repo_owned_target_remnants" in text
    assert "$candidates = @()" in text, "single latest run must remain an array under strict mode"
    assert "$results = @()" in text, "single target result must remain an array under strict mode"
    assert "$events = @()" in text, "single event sequence must have an explicit array baseline"


def test_e2e_proves_transient_removal_and_package_preservation() -> None:
    text = read(E2E)
    for fragment in (
        "post-install-transient.ps1",
        "CopyThenInstall",
        "Invoke-SasValidatedSoftwareDeployment.ps1",
        "requested software evidence was removed",
        "requested_software_preserved_after_teardown",
        "real_production_installer_wrapper_executed = $true",
        "real_finalization_gate_executed = $true",
        "journey-owned child directory",
        "foreach ($ownedPath in",
    ):
        assert fragment in text
    assert "[IO.Directory]::Delete($OutputRoot, $true)" not in text
    assert "$OutputRoot.Equals($approvedE2ERoot" in text


def test_harness_and_offline_runner_require_finalization_proof() -> None:
    profile = json.loads(read(PROFILE))
    journeys = {item["id"]: item for item in profile["journeys"]}
    assert "software-install-validated-finalization" in journeys
    assert journeys["software-install-validated-finalization"]["required"] is True
    default = next(item for item in profile["profiles"] if item["id"] == "default")
    assert "software-install-validated-finalization" in default["journey_ids"]
    workflow = read(WORKFLOW)
    assert "test_software_install_finalization_contracts.py" in workflow
    assert "software-install-validated-finalization" in workflow
    assert "test_software_install_finalization_contracts.py" in read(OFFLINE)


def test_cmd_is_zero_argument_result_entrypoint() -> None:
    text = read(CMD)
    assert 'if not "%~1"==""' in text
    assert "Show-SasValidatedSoftwareDeploymentResult.ps1" in text
    assert "-RequireCompleted" in text
    assert "exit /b 2" in text


def test_first_pilot_docs_enforce_confirmation_enabled() -> None:
    import re

    harness_doc = ROOT / "docs" / "SOFTWARE_INSTALL_HARNESS.md"
    finalization_doc = DOC

    for doc_path in (finalization_doc, harness_doc):
        text = read(doc_path)
        assert "Do not add `-Confirm:$false` during the first real pilot" in text, (
            f"{doc_path.name} must explicitly prohibit -Confirm:$false on first pilot"
        )

    pilot_section = read(finalization_doc).split("## Request authority", 1)[0]
    pilot_commands = re.findall(r"```powershell\n(.*?)```", pilot_section, re.DOTALL)
    assert pilot_commands, "finalization doc must contain a pilot PowerShell example"
    assert all(
        "-Confirm:$false" not in cmd for cmd in pilot_commands
    ), "finalization doc pilot example must not include -Confirm:$false"

    harness_text = read(harness_doc)
    approved_section = harness_text.split("## Example approved execution", 1)[1]
    approved_section = approved_section.split("## Known operational limits", 1)[0]
    first_pilot_block = approved_section.split("For noninteractive", 1)[0]
    first_pilot_commands = re.findall(r"```powershell\n(.*?)```", first_pilot_block, re.DOTALL)
    assert first_pilot_commands, "harness doc first-pilot example must exist"
    assert all(
        "-Confirm:$false" not in cmd for cmd in first_pilot_commands
    ), "harness doc first-pilot example must not include -Confirm:$false"


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_") and callable(value)]
    for test in tests:
        test()
        print(f"PASS: {test.__name__}")
    print(f"PASS: {len(tests)} validated software finalization contracts")
