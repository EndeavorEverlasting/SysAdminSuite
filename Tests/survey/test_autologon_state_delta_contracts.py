#!/usr/bin/env python3
"""Static contracts for the auto-logon workstation state-delta lane."""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PS_SCRIPT = REPO_ROOT / "scripts" / "Invoke-SasAutoLogonStateDelta.ps1"
BASH_WRAPPER = REPO_ROOT / "survey" / "sas-autologon-state-delta.sh"
DOC = REPO_ROOT / "docs" / "AUTOLOGON_STATE_DELTA.md"


def read(path: Path) -> str:
    assert path.exists(), f"missing required file: {path}"
    return path.read_text(encoding="utf-8")


def test_entrypoints_and_docs_exist() -> None:
    for path in (PS_SCRIPT, BASH_WRAPPER, DOC):
        assert path.exists(), f"missing auto-logon state-delta surface: {path}"


def test_collector_has_before_after_and_assess_modes() -> None:
    content = read(PS_SCRIPT)
    for fragment in (
        "[ValidateSet('Before', 'After', 'Assess')]",
        '"run_manifest_{0}.json" -f $phase',
        "CONFIRMED_STATE_TRANSITION",
        "ALREADY_CONFIGURED_BEFORE",
        "NO_MATERIAL_CHANGE",
        "PARTIAL_CHANGE_REVIEW",
        "REGRESSION_REVIEW",
        "INCONCLUSIVE",
    ):
        assert fragment in content, f"missing state-delta contract: {fragment}"


def test_collector_uses_explicit_bounded_approved_targets() -> None:
    content = read(PS_SCRIPT)
    for fragment in (
        "[ValidateRange(1, 25)]",
        "TargetsCsv",
        "ComputerName",
        "No explicit targets were supplied",
        "Split the run to keep remote reads bounded",
        "Assert-SasApprovedInputPath -Path $TargetsCsv",
        "auto-logon target manifest",
    ):
        assert fragment in content, f"missing target-boundary contract: {fragment}"


def test_default_password_data_is_never_read_or_exported() -> None:
    content = read(PS_SCRIPT)
    assert "Test-RegistryValueNameSafe -Path $winlogonPath -Name 'DefaultPassword'" in content
    assert "default_password_value_collected = $false" in content
    assert "GetValueNames()" in content

    forbidden = (
        "Get-RegistryValueSafe -Path $winlogonPath -Name 'DefaultPassword'",
        "Get-ItemPropertyValue -Path $winlogonPath -Name 'DefaultPassword'",
        "default_password =",
        "password_value =",
    )
    lowered = content.lower()
    for fragment in forbidden:
        assert fragment.lower() not in lowered, f"forbidden password-data collection fragment: {fragment}"


def test_autologon_ready_requires_default_password_presence() -> None:
    content = read(PS_SCRIPT)
    required = (
        "[bool]$PasswordPresent",
        "configured_password_missing",
        "$enabled -and $actual -eq $expected -and -not $PasswordPresent",
        "$enabled -and $actual -eq $expected -and $PasswordPresent",
        "-PasswordPresent ([bool]$passwordPresent)",
    )
    for fragment in required:
        assert fragment in content, f"missing fail-closed password-presence gate: {fragment}"


def test_installed_software_inventory_avoids_product_class_queries() -> None:
    content = read(PS_SCRIPT)
    assert "CurrentVersion\\Uninstall" in content
    assert "WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall" in content

    forbidden_product_class = "Win32" + "_Product"
    assert forbidden_product_class.lower() not in content.lower()


def test_evidence_stays_on_admin_box_and_collection_is_read_only() -> None:
    content = read(PS_SCRIPT)
    required = (
        "target_mutation_performed = $false",
        "target_side_sysadminsuite_artifacts_written = $false",
        "no_target_side_sysadminsuite_artifacts",
        "survey/output/autologon_state_delta",
        "Assert-SasApprovedOutputPath",
        "Assert-SasNorthwellWifi",
    )
    for fragment in required:
        assert fragment in content, f"missing read-only/local-evidence contract: {fragment}"

    forbidden = (
        "Copy-Item -ToSession",
        "New-ScheduledTask",
        "Register-ScheduledTask",
        "Set-ItemProperty",
        "New-ItemProperty",
        "Remove-ItemProperty",
        "Clear-EventLog",
        "wevtutil cl",
    )
    lowered = content.lower()
    for fragment in forbidden:
        assert fragment.lower() not in lowered, f"forbidden target-mutation fragment: {fragment}"


def test_summary_materializes_generic_list_without_binder_failure() -> None:
    content = read(PS_SCRIPT)
    assert "results = $rows.ToArray()" in content
    assert "results = @($rows)" not in content


def test_state_delta_does_not_claim_human_actor_identity() -> None:
    content = read(PS_SCRIPT)
    doc = read(DOC)
    for fragment in (
        "technician_execution_proven = $false",
        "actor_attribution = 'not_proven_by_state_delta'",
        "state_delta_does_not_prove_human_identity",
    ):
        assert fragment in content, f"missing attribution boundary: {fragment}"
    assert "A workstation delta proves state, not human identity." in doc


def test_fixture_mode_is_offline_and_wrapper_is_bash_on_windows() -> None:
    ps_content = read(PS_SCRIPT)
    bash_content = read(BASH_WRAPPER)
    doc = read(DOC)

    assert "[switch]$FixtureMode" in ps_content
    assert "no_network_activity" in ps_content
    assert "--fixture-mode" in bash_content
    assert "powershell.exe" in bash_content
    assert "pwsh.exe" in bash_content
    assert "Fixture success is contract proof only" in doc


def test_documented_pilot_requires_runtime_observation() -> None:
    content = read(DOC)
    required = (
        "capture Before state",
        "capture After state",
        "At least one reboot/logon observation",
        "The registry delta proves configuration posture",
        "real reboot and observed auto-logon",
    )
    for fragment in required:
        assert fragment in content, f"missing pilot/runtime-proof requirement: {fragment}"


def main() -> None:
    tests = [
        test_entrypoints_and_docs_exist,
        test_collector_has_before_after_and_assess_modes,
        test_collector_uses_explicit_bounded_approved_targets,
        test_default_password_data_is_never_read_or_exported,
        test_autologon_ready_requires_default_password_presence,
        test_installed_software_inventory_avoids_product_class_queries,
        test_evidence_stays_on_admin_box_and_collection_is_read_only,
        test_summary_materializes_generic_list_without_binder_failure,
        test_state_delta_does_not_claim_human_actor_identity,
        test_fixture_mode_is_offline_and_wrapper_is_bash_on_windows,
        test_documented_pilot_requires_runtime_observation,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} auto-logon state-delta contracts")


if __name__ == "__main__":
    main()
