#!/usr/bin/env python3
"""Static contracts for the catalog-driven approved software install capsule."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "configs" / "software-packages" / "approved-apps.json"
CMD = ROOT / "Run-InstallApprovedSoftware.cmd"
LEGACY_CMD = ROOT / "Run-InstallAutoDidact.cmd"
SCRIPT = ROOT / "scripts" / "Start-SasAutoDidactInstall.ps1"
DOC = ROOT / "docs" / "AUTODIDACT_INSTALL_WORKFLOW.md"
RUNNER = ROOT / "tests" / "survey" / "run_offline_survey_tests.sh"


def read(path: Path) -> str:
    assert path.exists(), f"missing expected file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def load_catalog() -> dict:
    return json.loads(read(CATALOG))


def package_map() -> dict[str, dict]:
    catalog = load_catalog()
    return {package["id"]: package for package in catalog["packages"]}


def test_catalog_is_folder_first_and_uses_approved_server_root() -> None:
    catalog = load_catalog()
    assert catalog["schema_version"] == "sas-approved-software-catalog/v1"
    assert catalog["software_share_root"] == "\\\\nt2kwb972sms01\\"
    assert catalog["package_root_relative_path"] == "packages"

    policy = catalog["catalog_policy"]
    assert policy["folder_first"] is True
    assert policy["requires_admin_context"] is True
    assert policy["snapshot_required_before_install"] is True
    assert policy["require_pinned_installer_file_for_plan_or_install"] is True
    assert policy["require_vendor_validated_installer_arguments_for_live_install"] is True


def test_catalog_records_epic_allscripts_and_autologon_paths() -> None:
    packages = package_map()
    assert set(packages) == {
        "epic-satellite",
        "allscripts-touchworks-22-1",
        "autologon",
    }

    epic = packages["epic-satellite"]
    assert epic["source_folder_relative_path"] == r"packages\Epic\Satellite"
    assert epic["installer_file"] is None
    assert epic["install_enabled"] is False
    assert epic["readiness"] == "installer_file_pending"

    allscripts = packages["allscripts-touchworks-22-1"]
    assert allscripts["source_folder_relative_path"] == r"packages\TouchWork_22.1"
    assert allscripts["installer_file"] == "TWInstaller.exe"
    assert allscripts["install_enabled"] is True

    autologon = packages["autologon"]
    assert autologon["source_folder_relative_path"] == r"packages\AutoLogonSetup"
    assert autologon["installer_file"] == "NW_AutoLogon_Setup_x64.exe"
    assert autologon["default_install_mode"] == "CopyThenInstall"
    assert autologon["install_enabled"] is True

    for package in packages.values():
        folder = package["source_folder_relative_path"]
        assert not folder.startswith("\\\\"), "catalog package folders must stay relative"
        assert ".." not in folder.split("\\"), "catalog package folders cannot traverse parents"
        assert package["default_installer_arguments"] == []
        assert package["requires_validated_installer_arguments"] is True


def test_canonical_and_legacy_cmd_launchers_are_repo_relative() -> None:
    content = read(CMD)
    required = [
        "SysAdminSuite - Approved Software Install",
        "Catalog: Epic, AllScripts, AutoLogon",
        "Snapshot protocol: BEFORE snapshot - plan/install - AFTER snapshot",
        "scripts\\Start-SasAutoDidactInstall.ps1",
        "-Action Menu",
        "survey\\output\\approved_software_install",
        "exit /b %EXITCODE%",
    ]
    for fragment in required:
        assert fragment in content, f"missing canonical CMD fragment: {fragment}"

    legacy = read(LEGACY_CMD)
    assert 'call "%~dp0Run-InstallApprovedSoftware.cmd" %*' in legacy
    assert "exit /b %EXITCODE%" in legacy


def test_wrapper_loads_catalog_and_does_not_prompt_for_raw_installer_paths() -> None:
    content = read(SCRIPT)
    required = [
        "configs/software-packages/approved-apps.json",
        "sas-approved-software-catalog/v1",
        "Get-SasApprovedPackageCatalog",
        "Select-SasApprovedPackage",
        "Get-SasPackageInstallerRelativePath",
        "Show-SasApprovedPackages",
        "PackageId is required for noninteractive approved software work",
        "Select package number or enter package id",
        "Catalog: Epic, AllScripts, AutoLogon",
    ]
    for fragment in required:
        assert fragment in content, f"missing package catalog wrapper fragment: {fragment}"

    assert "[string]$InstallerRelativePath" not in content
    assert "Auto Didact installer path relative to approved software root" not in content
    assert "Get-ChildItem -LiteralPath $catalogRoot" not in content


def test_before_snapshot_is_required_and_bound_to_selected_package() -> None:
    content = read(SCRIPT)
    required = [
        "Assert-SasBeforeSnapshotReady",
        "Before snapshot must complete before approved software install",
        "package_id = [string]$package.id",
        "package_name = [string]$package.display_name",
        "installer_relative_path = $installerRelativePath",
        "snapshot_required_before_install = $true",
        "workflow_status = 'before_complete'",
        "The catalog installer path changed after the Before snapshot",
    ]
    for fragment in required:
        assert fragment in content, f"missing snapshot/package binding fragment: {fragment}"

    before_gate = content.index(
        "Assert-SasBeforeSnapshotReady -ManifestPath ([string]$state.before_manifest_path)"
    )
    install_call = content.index(
        "& $installScript @params -AllowTargetMutation -Confirm:$false"
    )
    assert before_gate < install_call


def test_plan_and_live_install_fail_closed_on_catalog_readiness() -> None:
    content = read(SCRIPT)
    required = [
        "Assert-SasPackagePlanReady",
        "Package '$($Package.display_name)' is not enabled for plan/install",
        "has no pinned installer filename",
        "Assert-SasPackageLiveReady",
        "requires explicit vendor-validated installer arguments",
        "PackageName = [string]$package.display_name",
        "SoftwareShareRoot = [string]$catalog.software_share_root",
        "InstallerRelativePath = $installerRelativePath",
        "InstallMode = [string]$package.default_install_mode",
        "-WhatIf",
        "-AllowTargetMutation",
        "-Confirm:$false",
    ]
    for fragment in required:
        assert fragment in content, f"missing fail-closed install fragment: {fragment}"


def test_snapshots_are_read_only_admin_box_evidence() -> None:
    content = read(SCRIPT)
    required = [
        "sas-approved-software-snapshot/v1",
        "sas-approved-software-snapshot-manifest/v1",
        "installed_software",
        "target_mutation_performed = $false",
        "target_side_sysadminsuite_artifacts_written = $false",
        "Assert-SasApprovedOutputPath -Path $OutputRoot",
        "Assert-SasApprovedInputPath -Path $CsvPath",
        "survey/output/approved_software_install",
        "no_target_side_sysadminsuite_artifacts",
        "no_target_mutation",
    ]
    for fragment in required:
        assert fragment in content, f"missing read-only snapshot fragment: {fragment}"

    lowered = content.lower()
    forbidden = [
        "win32_product",
        "defaultpassword",
        "clear-eventlog",
        "wevtutil cl",
        "start-transcript",
        "stop-transcript",
        "-credential",
        "register-scheduledtask",
        "new-service",
    ]
    for fragment in forbidden:
        assert fragment not in lowered, f"forbidden fragment present: {fragment}"


def test_documented_catalog_flow_and_readiness_boundaries() -> None:
    content = read(DOC)
    required = [
        "Run-InstallApprovedSoftware.cmd",
        "Run-InstallAutoDidact.cmd",
        "configs/software-packages/approved-apps.json",
        "Epic Satellite",
        "AllScripts TouchWorks 22.1",
        "NW AutoLogon Setup x64",
        "packages\\Epic\\Satellite",
        "packages\\TouchWork_22.1\\TWInstaller.exe",
        "packages\\AutoLogonSetup\\NW_AutoLogon_Setup_x64.exe",
        "BEFORE snapshot",
        "WhatIf install plan",
        "AFTER snapshot",
        "does not search a package folder for the newest executable",
        "vendor-validated installer arguments",
        "It does not prove application launch, user acceptance, or business behavior",
    ]
    for fragment in required:
        assert fragment in content, f"missing documentation fragment: {fragment}"


def test_offline_runner_wires_catalog_contract() -> None:
    content = read(RUNNER)
    assert "python3 Tests/survey/test_autodidact_install_capsule_contracts.py" in content


def main() -> None:
    tests = [
        test_catalog_is_folder_first_and_uses_approved_server_root,
        test_catalog_records_epic_allscripts_and_autologon_paths,
        test_canonical_and_legacy_cmd_launchers_are_repo_relative,
        test_wrapper_loads_catalog_and_does_not_prompt_for_raw_installer_paths,
        test_before_snapshot_is_required_and_bound_to_selected_package,
        test_plan_and_live_install_fail_closed_on_catalog_readiness,
        test_snapshots_are_read_only_admin_box_evidence,
        test_documented_catalog_flow_and_readiness_boundaries,
        test_offline_runner_wires_catalog_contract,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} approved software catalog contracts")


if __name__ == "__main__":
    main()
