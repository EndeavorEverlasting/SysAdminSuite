#!/usr/bin/env python3
"""Contracts for stale-checkout-safe Cybernet software deployment.

These tests are repository-only. They do not contact GitHub, a package share, or a
field target and they never start installation or restart behavior.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(relative: str) -> str:
    path = ROOT / relative
    assert path.is_file(), f"missing required deployment surface: {relative}"
    return path.read_text(encoding="utf-8-sig")


def test_current_launcher_refuses_checkout_local_deployment_authority() -> None:
    launcher = read("Deploy-CybernetSoftware.cmd")
    lowered = launcher.lower()
    assert 'set "sealed_runtime=c:\\sasal"' in lowered
    assert 'bootstrap-sysadminsuitecybernetsoftware.cmd' in lowered
    assert 'call "%sealed_bootstrap%" "%~2"' in lowered
    assert 'this checkout is not deployment authority' in lowered
    assert 'sas refresh' in lowered
    assert 'start-here-admin-box-software-deployment.md' in lowered
    assert 'powershell.exe -nologo -noprofile -executionpolicy bypass -file "%script_dir%scripts\\invoke-sascybernetsoftwaredeployment.ps1"' not in lowered


def test_cmd_bootstrap_is_only_valid_from_fixed_canonical_runtime() -> None:
    bootstrap = read("Bootstrap-SysAdminSuiteCybernetSoftware.cmd")
    lowered = bootstrap.lower()
    assert 'set "sas_canonical_runtime=c:\\sasal"' in lowered
    assert 'if /i not "%sas_runtime%"=="%sas_canonical_runtime%"' in lowered
    assert "cybernet_sealed_runtime_authority_invalid" in lowered
    assert "no manifest resolution, target contact, or mutation was started" in lowered
    assert "invoke-sascybernetsealedsoftwarebootstrap.ps1" in lowered
    assert "$env:sas_cybernet_explicit_target" in lowered
    assert "invoke-sascybernetsoftwaredeployment.ps1" not in lowered


def test_sealed_admission_orders_actual_executable_gates_before_engine() -> None:
    admission = read("scripts/Invoke-SasCybernetSealedSoftwareBootstrap.ps1")
    lowered = admission.lower()
    resolver_call = lowered.index(
        "invoke-saschildpowershell -powershellexe $psexe -scriptpath $manifestresolver"
    )
    audit_call = lowered.index(
        "invoke-saschildpowershell -powershellexe $psexe -scriptpath $auditscript"
    )
    lock_call = lowered.index(
        "lock-sastrackedruntime -canonicalruntime $runtimefull -manifest $manifest"
    )
    engine_call = lowered.index(
        "& $enginescript -computername $target -allowtargetmutation -confirmdeployment -passthru"
    )
    assert resolver_call < audit_call < lock_call < engine_call
    assert "-requiremanifest" in lowered
    assert "target = $computername.trim().trimend('.')" in lowered
    assert "cybernet_sealed_target_invalid" in lowered


def test_tracked_runtime_is_rehashed_under_write_delete_exclusion_for_deployment_lifetime() -> None:
    admission = read("scripts/Invoke-SasCybernetSealedSoftwareBootstrap.ps1")
    lowered = admission.lower()
    assert "[io.fileshare]::read" in lowered
    assert "get-sassha256fromstream -stream $stream" in lowered
    assert "cybernet_sealed_runtime_recheck_mismatch" in lowered
    assert "cybernet_sealed_runtime_locked" in lowered
    engine_call = lowered.index(
        "& $enginescript -computername $target -allowtargetmutation -confirmdeployment -passthru"
    )
    finally_block = lowered.index("finally {", engine_call)
    unlock_call = lowered.index("close-sasruntimelocks -locks $locks", finally_block)
    assert engine_call < finally_block < unlock_call
    assert "parent\n    # process therefore retains every tracked-file lock until the complete deployment call returns" in lowered


def test_protected_admission_contains_no_remote_git_fallback() -> None:
    combined = (
        read("Bootstrap-SysAdminSuiteCybernetSoftware.cmd")
        + "\n"
        + read("scripts/Invoke-SasCybernetSealedSoftwareBootstrap.ps1")
    ).lower()
    for forbidden in (
        "git fetch",
        "git pull",
        "git clone",
        "github.com",
        "remote add",
        "remote set-url",
    ):
        assert forbidden not in combined, f"protected admission contains remote Git fallback: {forbidden}"


def test_manifest_and_full_seal_are_pre_target_local_only_authorities() -> None:
    resolver = read("scripts/Resolve-SasAutoLogonManifestAuthority.ps1").lower()
    audit = read("scripts/Test-SasAutoLogonRuntimeSeal.ps1").lower()
    for text in (resolver, audit):
        assert "network_activity_performed = $false" in text
        assert "target_contact_performed = $false" in text
        assert "target_mutation_performed = $false" in text
    assert "tracked_file_hashes" in audit
    assert "hash_mismatch" in audit
    assert "missing_file" in audit
    assert "local_filesystem_only" in audit
    assert "runtime_remotes_removed" in audit


def test_guest_bootstrap_refreshes_verifies_surface_then_installs_universal_surface() -> None:
    bootstrap = read("Bootstrap-SysAdminSuiteFieldRuntime.cmd")
    lowered = bootstrap.lower()
    invoke_refresh = lowered.index(
        '"%sas_ps%" -nologo -noprofile -executionpolicy bypass -file "%sas_refresh%"'
    )
    surface_gate = lowered.index("=== verifying complete protected cybernet surface ===")
    admission_required = lowered.index('"%sas_cybernet_admission%"', surface_gate)
    invoke_universal = lowered.index(
        '"%sas_ps%" -nologo -noprofile -executionpolicy bypass -file "%sas_universal_installer%"'
    )
    ready = lowered.index("sas_field_runtime_bootstrap_ready")
    assert invoke_refresh < surface_gate < admission_required < invoke_universal < ready
    for required in (
        "c:\\sasal\\deploy-cybernetsoftware.cmd",
        "c:\\sasal\\bootstrap-sysadminsuitecybernetsoftware.cmd",
        "c:\\sasal\\scripts\\invoke-sascybernetsealedsoftwarebootstrap.ps1",
        "c:\\sasal\\scripts\\invoke-sascybernetsoftwaredeployment.ps1",
        "c:\\sasal\\scripts\\resolve-sasautologonmanifestauthority.ps1",
        "c:\\sasal\\scripts\\test-sasautologonruntimeseal.ps1",
    ):
        assert required in lowered
    assert "network required: guest / internet" in lowered
    assert "protected cybernet surface: verified" in lowered
    assert "no protected target deployment was started" in lowered
    assert "existing desktop/onedrive checkouts are not reset, cleaned, or reused as deployment authority" in lowered


def test_admin_box_runbook_contains_copy_safe_fresh_main_acquisition_and_recovery() -> None:
    runbook = read("START-HERE-ADMIN-BOX-SOFTWARE-DEPLOYMENT.md")
    lowered = runbook.lower()
    for marker in (
        "git clone --branch main --single-branch https://github.com/endeavoreverlasting/sysadminsuite.git $dst",
        "$env:localappdata",
        "bootstrap-sysadminsuitefieldruntime.cmd",
        "sas_field_runtime_bootstrap_ready",
        "sas cybernet deploy <authorized-cybernet>",
        "c:\\sasal\\bootstrap-sysadminsuitecybernetsoftware.cmd",
        "fileaccess.read",
        "cybernet_software_deployment_completed_restarted",
        "sas evidence cybernet open",
        "protected-side git network activity is `none`",
        "old admin-box checkouts",
    ):
        assert marker in lowered, f"runbook missing: {marker}"
    assert "do not reset, clean, rebase, delete, or rehabilitate them" in lowered
    assert "guest / internet" in lowered and "protected northwell" in lowered
    assert "second sha-256 verification" in lowered
    assert "locks are released only after the deployment call returns" in lowered


def test_current_sas_route_still_reaches_the_hardened_launcher() -> None:
    portable = read("scripts/SasPortableLauncher.ps1")
    platform = read("scripts/SasFieldPlatform.psm1")
    portable_lower = portable.lower()
    resolve = platform[platform.index("function Resolve-SasControllerRoot"):]
    assert "sas cybernet Deploy HOST" in portable
    assert "Deploy-CybernetSoftware.cmd" in portable
    assert "if ($mode -eq 'deploy')" in portable
    assert portable_lower.index("if ($mode -eq 'deploy')") < portable_lower.index(
        "deploy-cybernetsoftware.cmd", portable_lower.index("if ($mode -eq 'deploy')")
    )
    runtime_candidate = resolve.index(
        "Add-SasControllerCandidate -List $candidates -Path $script:SasDefaultRuntimeRoot"
    )
    repo_candidate = resolve.index(
        "Add-SasControllerCandidate -List $candidates -Path $env:SAS_REPO_ROOT"
    )
    assert runtime_candidate < repo_candidate, "C:\\SASAL must outrank an arbitrary checkout for the universal field controller"


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} sealed Cybernet deployment bootstrap contract groups")


if __name__ == "__main__":
    main()
