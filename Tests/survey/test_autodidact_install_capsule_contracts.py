#!/usr/bin/env python3
"""Static contracts for the Auto Didact install command capsule."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CMD = ROOT / "Run-InstallAutoDidact.cmd"
SCRIPT = ROOT / "scripts" / "Start-SasAutoDidactInstall.ps1"
DOC = ROOT / "docs" / "AUTODIDACT_INSTALL_WORKFLOW.md"
RUNNER = ROOT / "tests" / "survey" / "run_offline_survey_tests.sh"


def read(path: Path) -> str:
    assert path.exists(), f"missing expected file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def test_cmd_launcher_exists_and_uses_repo_relative_script() -> None:
    content = read(CMD)
    required = [
        "SysAdminSuite - Auto Didact Install",
        "Snapshot protocol: BEFORE snapshot - plan/install - AFTER snapshot",
        "scripts\\Start-SasAutoDidactInstall.ps1",
        "-Action Menu",
        "exit /b %EXITCODE%",
    ]
    for fragment in required:
        assert fragment in content, f"missing CMD launcher fragment: {fragment}"


def test_autodidact_script_composes_existing_install_wrapper() -> None:
    content = read(SCRIPT)
    required = [
        "Invoke-SasSoftwareInstall.ps1",
        "PackageName = 'Auto Didact'",
        "InstallerRelativePath = [string]$state.installer_relative_path",
        "InstallerArguments = @($state.installer_arguments)",
        "-WhatIf",
        "-AllowTargetMutation",
        "-Confirm:$false",
        "Install Auto Didact after confirmed BEFORE snapshot",
    ]
    for fragment in required:
        assert fragment in content, f"missing install composition fragment: {fragment}"


def test_before_snapshot_is_required_before_install() -> None:
    content = read(SCRIPT)
    required = [
        "Assert-SasBeforeSnapshotReady",
        "Before snapshot must complete before Auto Didact install",
        "before_manifest_path",
        "snapshot_required_before_install = $true",
        "workflow_status = 'before_complete'",
        "workflow_status = 'install_attempted'",
    ]
    for fragment in required:
        assert fragment in content, f"missing snapshot gate fragment: {fragment}"

    before_gate = content.index("Assert-SasBeforeSnapshotReady -ManifestPath ([string]$state.before_manifest_path)")
    install_call = content.index("& $installScript @params -AllowTargetMutation -Confirm:$false")
    assert before_gate < install_call


def test_snapshots_are_read_only_and_admin_box_local() -> None:
    content = read(SCRIPT)
    required = [
        "schema_version = 'sas-autodidact-software-snapshot/v1'",
        "snapshot_phase = $Phase",
        "installed_software",
        "target_mutation_performed = $false",
        "target_side_sysadminsuite_artifacts_written = $false",
        "Assert-SasApprovedOutputPath -Path $OutputRoot",
        "Assert-SasApprovedInputPath -Path $CsvPath",
        "survey/output/autodidact_install",
        "no_target_side_sysadminsuite_artifacts",
        "no_target_mutation",
    ]
    for fragment in required:
        assert fragment in content, f"missing read-only snapshot fragment: {fragment}"


def test_snapshot_collector_avoids_product_class_and_secret_collection() -> None:
    content = read(SCRIPT)
    lowered = content.lower()
    assert "CurrentVersion\\Uninstall" in content
    assert "WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall" in content
    forbidden = [
        "Win32_Product",
        "DefaultPassword",
        "Get-ItemPropertyValue",
        "Clear-EventLog",
        "wevtutil cl",
        "Start-Transcript",
        "Stop-Transcript",
        "-Credential",
        "Register-ScheduledTask",
        "New-Service",
    ]
    for fragment in forbidden:
        assert fragment.lower() not in lowered, f"forbidden fragment present: {fragment}"


def test_documented_operator_flow_and_proof_boundary() -> None:
    content = read(DOC)
    required = [
        "Run-InstallAutoDidact.cmd",
        "BEFORE snapshot",
        "WhatIf install plan",
        "approved Auto Didact install",
        "AFTER snapshot",
        "The before snapshot must complete before the install action can run",
        "\\\\nt2kwb972sms01\\",
        "scripts/Invoke-SasSoftwareInstall.ps1",
        "It does not prove application launch, user acceptance, or business behavior",
        "production-ready as a guarded command surface",
    ]
    for fragment in required:
        assert fragment in content, f"missing documentation fragment: {fragment}"


def test_offline_runner_wires_autodidact_contract() -> None:
    content = read(RUNNER)
    assert "python3 Tests/survey/test_autodidact_install_capsule_contracts.py" in content


def main() -> None:
    tests = [
        test_cmd_launcher_exists_and_uses_repo_relative_script,
        test_autodidact_script_composes_existing_install_wrapper,
        test_before_snapshot_is_required_before_install,
        test_snapshots_are_read_only_and_admin_box_local,
        test_snapshot_collector_avoids_product_class_and_secret_collection,
        test_documented_operator_flow_and_proof_boundary,
        test_offline_runner_wires_autodidact_contract,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} Auto Didact install capsule contracts")


if __name__ == "__main__":
    main()
