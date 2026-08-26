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


def test_sealed_bootstrap_audits_before_any_deployment_engine_execution() -> None:
    bootstrap = read("Bootstrap-SysAdminSuiteCybernetSoftware.cmd")
    lowered = bootstrap.lower()
    resolver = lowered.index("resolve-sasautologonmanifestauthority.ps1")
    audit = lowered.index("test-sasautologonruntimeseal.ps1")
    engine = lowered.index("invoke-sascybernetsoftwaredeployment.ps1")
    execute = lowered.rindex('"%sas_ps%" -nologo -noprofile -executionpolicy bypass -file "%sas_engine%"')
    assert resolver < audit < engine < execute
    assert "-requiremanifest" in lowered
    assert "-allowtargetmutation -confirmdeployment" in lowered
    assert "target contact before seal audit: none" in lowered
    assert "target mutation before seal audit: none" in lowered
    assert "git network activity: none" in lowered
    assert "sas evidence cybernet open" in lowered


def test_protected_bootstrap_contains_no_remote_git_fallback() -> None:
    bootstrap = read("Bootstrap-SysAdminSuiteCybernetSoftware.cmd").lower()
    for forbidden in (
        "git fetch",
        "git pull",
        "git clone",
        "github.com",
        "remote add",
        "remote set-url",
    ):
        assert forbidden not in bootstrap, f"protected bootstrap contains remote Git fallback: {forbidden}"


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


def test_guest_bootstrap_refreshes_then_installs_universal_surface() -> None:
    bootstrap = read("Bootstrap-SysAdminSuiteFieldRuntime.cmd")
    lowered = bootstrap.lower()
    refresh = lowered.index("refresh-sasoperatorcommand.ps1")
    universal = lowered.index("c:\\sasal\\scripts\\install-sasuniversalfieldlauncher.ps1")
    invoke_refresh = lowered.index('"%sas_ps%" -nologo -noprofile -executionpolicy bypass -file "%sas_refresh%"')
    invoke_universal = lowered.index('"%sas_ps%" -nologo -noprofile -executionpolicy bypass -file "%sas_universal_installer%"')
    assert refresh < invoke_refresh < invoke_universal
    assert universal < invoke_universal
    assert "network required: guest / internet" in lowered
    assert "sas_field_runtime_bootstrap_ready" in lowered
    assert "no protected target deployment was started" in lowered
    assert "existing desktop/onedrive checkouts are not reset, cleaned, or reused as deployment authority" in lowered


def test_admin_box_runbook_preserves_old_checkouts_and_splits_network_authority() -> None:
    runbook = read("START-HERE-ADMIN-BOX-SOFTWARE-DEPLOYMENT.md")
    lowered = runbook.lower()
    for marker in (
        "bootstrap-sysadminsuitefieldruntime.cmd",
        "sas cybernet deploy <authorized-cybernet>",
        "c:\\sasal\\bootstrap-sysadminsuitecybernetsoftware.cmd",
        "cybernet_software_deployment_completed_restarted",
        "sas evidence cybernet open",
        "protected-side git network activity is `none`",
        "old admin-box checkouts",
    ):
        assert marker in lowered, f"runbook missing: {marker}"
    assert "do not reset, clean, rebase, delete, or rehabilitate them" in lowered
    assert "guest / internet" in lowered and "protected northwell" in lowered


def test_current_sas_route_still_reaches_the_hardened_launcher() -> None:
    portable = read("scripts/SasPortableLauncher.ps1")
    platform = read("scripts/SasFieldPlatform.psm1")
    portable_lower = portable.lower()
    resolve = platform[platform.index("function Resolve-SasControllerRoot"):]
    assert "sas cybernet Deploy HOST" in portable
    assert "Deploy-CybernetSoftware.cmd" in portable
    assert "if ($mode -eq 'deploy')" in portable
    assert portable_lower.index("if ($mode -eq 'deploy')") < portable_lower.index("deploy-cybernetsoftware.cmd", portable_lower.index("if ($mode -eq 'deploy')"))
    runtime_candidate = resolve.index("Add-SasControllerCandidate -List $candidates -Path $script:SasDefaultRuntimeRoot")
    repo_candidate = resolve.index("Add-SasControllerCandidate -List $candidates -Path $env:SAS_REPO_ROOT")
    assert runtime_candidate < repo_candidate, "C:\\SASAL must outrank an arbitrary checkout for the universal field controller"


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} sealed Cybernet deployment bootstrap contract groups")


if __name__ == "__main__":
    main()
