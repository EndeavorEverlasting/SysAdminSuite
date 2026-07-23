#!/usr/bin/env python3
"""Static contracts for AutoLogon canonical LocalSystem qualification."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POLICY = ROOT / "configs" / "software-packages" / "autologon-system-qualification.json"
REQUEST_TEMPLATE = ROOT / "configs" / "software-packages" / "autologon-system-qualification-request.example.json"
QUALIFICATION_CATALOG = ROOT / "configs" / "software-packages" / "autologon-system-qualification-catalog.json"
APPROVED = ROOT / "configs" / "software-packages" / "approved-apps.json"
PACKAGE_SETS = ROOT / "configs" / "software-packages" / "windows-native-package-sets.json"
SCRIPT = ROOT / "scripts" / "Invoke-SasAutoLogonSystemQualification.ps1"
AUTOLOGON_DEPLOYMENT = ROOT / "scripts" / "Invoke-SasAutoLogonDeployment.ps1"
APPROVED_INSTALL = ROOT / "scripts" / "Start-SasApprovedSoftwareInstall.ps1"
BASH_INSTALL = ROOT / "bash" / "apps" / "sas-install-apps.sh"
CMD = ROOT / "Qualify-AutoLogonSystemPackage.cmd"
DOC = ROOT / "docs" / "AUTOLOGON_SYSTEM_QUALIFICATION.md"
PESTER = ROOT / "Tests" / "Pester" / "AutoLogonSystemQualification.Tests.ps1"
WORKFLOW = ROOT / ".github" / "workflows" / "autologon-system-qualification.yml"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required qualification surface: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def package(catalog: dict, package_id: str) -> dict:
    matches = [item for item in catalog.get("packages", []) if item.get("id") == package_id]
    assert len(matches) == 1, f"package {package_id} missing or ambiguous"
    return matches[0]


def test_required_surfaces_exist() -> None:
    for path in (POLICY, REQUEST_TEMPLATE, QUALIFICATION_CATALOG, APPROVED, PACKAGE_SETS, SCRIPT, CMD, DOC, PESTER, WORKFLOW):
        assert path.is_file(), path


def test_runtime_failure_is_recorded_as_contract_not_administration() -> None:
    policy = load(POLICY)
    assert policy["schema_version"] == "sas-autologon-system-qualification-policy/v1"
    assert policy["status"] == "qualification_required"
    assert policy["canonical_system_install_enabled"] is False
    observed = policy["failed_runtime_observation"]
    assert observed["execution_identity"] == "S-1-5-18"
    assert observed["installer_exit_code"] == 0
    assert observed["installer_arguments"] == []
    assert observed["classification"] == "exit_zero_required_postcondition_missing"
    assert "AutoAdminLogon=1" in observed["required_postcondition"]


def test_production_catalogs_remain_plannable_but_fail_closed_before_worker_generation() -> None:
    approved = package(load(APPROVED), "autologon")
    native = package(load(PACKAGE_SETS), "autologon")
    for item in (approved, native):
        assert item["install_enabled"] is True
        assert item["canonical_system_install_enabled"] is False
        qualification = item["canonical_system_qualification"]
        assert qualification["status"] == "failed_runtime_validation"
        assert qualification["qualified_installer_sha256"] is None
        assert qualification["qualified_package_version"] is None
        assert qualification["qualified_installer_arguments"] is None
    assert approved["readiness"] == "installer_and_no_arguments_confirmed"

    autologon_deployment = read(AUTOLOGON_DEPLOYMENT)
    approved_install = read(APPROVED_INSTALL)
    bash_install = read(BASH_INSTALL)
    for content in (autologon_deployment, approved_install, bash_install):
        assert "canonical_system_install_enabled" in content
        assert "blocked" in content.lower()
    assert autologon_deployment.index("if ($WhatIfPreference -and -not $FixtureMode)") < (
        autologon_deployment.index(
            "if (-not $FixtureMode -and -not [bool]$package.canonical_system_install_enabled)"
        )
    )


def test_qualification_catalog_is_narrow_and_not_a_production_promotion() -> None:
    catalog = load(QUALIFICATION_CATALOG)
    assert catalog["catalog_policy"]["qualification_only"] is True
    assert catalog["catalog_policy"]["canonical_production_install_enabled"] is False
    candidate = package(catalog, "autologon")
    assert candidate["install_enabled"] is True
    assert candidate["readiness"] == "qualification_only"
    assert "cannot promote" in candidate["notes"].lower()


def test_request_requires_material_difference_and_evidence_backed_arguments() -> None:
    template = load(REQUEST_TEMPLATE)
    assert template["schema_version"] == "sas-autologon-system-qualification-request/v1"
    assert "failed_invocation" in template
    assert "installer_sha256" in template["failed_invocation"]
    assert "installer_arguments" in template["failed_invocation"]
    assert "installer_arguments_reference" in template
    script = read(SCRIPT)
    for marker in (
        "Candidate is identical to the failed LocalSystem hash-and-arguments invocation. Repeating it is forbidden.",
        "installer_arguments_reference must identify vendor documentation or the package owner decision.",
        "candidate_materially_differs_from_failed_invocation",
        "sameHash",
        "sameArguments",
    ):
        assert marker in script, marker


def test_live_lane_uses_only_certified_canonical_system_boundary() -> None:
    script = read(SCRIPT)
    required = (
        "Assert-SasNorthwellWifi",
        "Test-SasSoftwareDeploymentTransport.ps1",
        "-TransportIntent kerberos_smb_task",
        "Invoke-SasSoftwareDeploymentTransportLiveCert.ps1",
        "LIVE CERT PASS",
        "Invoke-SasAutoLogonSmbStateCapture",
        "Test-SasQualificationCleanBaseline",
        "Invoke-SasAutoLogonFinalStepGate.ps1",
        "autologon-system-qualification-catalog.json",
        "Invoke-SasValidatedSoftwareDeployment.ps1",
        "-Transport SmbScheduledTask",
        "postcondition_auto_admin_logon",
        "postcondition_default_password_name_present",
        "postcondition_expected_user_match",
        "QUALIFIED_FOR_CANONICAL_SYSTEM",
        "CANDIDATE_UNSUPPORTED_SYSTEM_POSTCONDITION",
        "autologon_system_qualification_receipt.json",
        "canonical_catalog_promoted = $false",
        "automatic_reboot_performed = $false",
        "automatic_sign_in_observed = $false",
        "Resolve-SasQualificationApprovedShareRoot",
        "Resolve-SasQualificationTargetIdentity",
        "Test-SasQualificationSnapshotIdentity",
        "installer_arguments_policy",
        "$null -ne $installerExitCode",
    )
    for marker in required:
        assert marker in script, marker
    assert script.index("Resolve-SasQualificationApprovedShareRoot") < script.index(
        "Test-Path -LiteralPath $installerPath"
    )
    assert "$errorMessage -match" not in script
    assert "promotion_required = true" not in script
    assert "reboot_observed = false" not in script
    assert "automatic_sign_in_observed = false" not in script
    lowered = script.lower()
    for forbidden in (
        "enable-psremoting",
        "winrm quickconfig",
        "restart-computer",
        "-credential",
        "set-itemproperty",
        "new-itemproperty",
        "remove-itemproperty",
    ):
        assert forbidden not in lowered, forbidden


def test_clean_baseline_and_one_candidate_rules_are_explicit() -> None:
    script = read(SCRIPT)
    doc = read(DOC)
    for marker in (
        "AutoLogon not configured and no existing NW AutoLogon Setup uninstall entry",
        "Use a fresh or explicitly reset pilot",
        "Test-SasQualificationCleanBaseline",
    ):
        assert marker in script, marker
    for marker in (
        "Do not test multiple candidates serially on the same altered workstation",
        "Each candidate requires one of:",
        "fresh authorized Cybernet pilot",
        "documented reset to a proven clean baseline",
    ):
        assert marker in doc, marker


def test_cmd_is_zero_argument_repo_relative_surface() -> None:
    cmd = read(CMD)
    for marker in (
        'if not "%~1"==""',
        'cd /d "%~dp0"',
        "%~dp0scripts\\Invoke-SasAutoLogonSystemQualification.ps1",
        "-Action Menu",
        "does not accept command-line arguments",
        "exit /b %EXITCODE%",
    ):
        assert marker in cmd, marker


def test_documentation_states_promotion_and_proof_ceiling() -> None:
    doc = read(DOC)
    for marker in (
        "canonical SYSTEM qualification",
        "Exit code `0` therefore does not satisfy the package contract",
        "QUALIFIED_FOR_CANONICAL_SYSTEM",
        "CANDIDATE_UNSUPPORTED_SYSTEM_POSTCONDITION",
        "Promotion is a separate bounded change",
        "install_enabled = true",
        "canonical_system_install_enabled = true",
        "does not prove:",
        "automatic sign-in",
    ):
        assert marker.lower() in doc.lower(), marker


def test_ci_is_fixture_only_and_preserves_checkout_credentials_boundary() -> None:
    workflow = read(WORKFLOW)
    for marker in (
        "persist-credentials: false",
        "test_autologon_system_qualification_contracts.py",
        "AutoLogonSystemQualification.Tests.ps1",
        "FixtureMode",
        "git diff --check",
    ):
        assert marker in workflow, marker
    assert "AllowNetworkActivity" not in workflow
    assert "AllowTargetMutation" not in workflow


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_") and callable(value)]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} AutoLogon SYSTEM qualification contracts")


if __name__ == "__main__":
    main()
