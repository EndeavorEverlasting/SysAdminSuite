#!/usr/bin/env python3
"""Static contracts for Guest-only sync, field-ready staging, and protected AutoLogon runtime use."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(relative: str) -> str:
    path = ROOT / relative
    assert path.is_file(), f"missing refresh surface: {relative}"
    return path.read_text(encoding="utf-8-sig")


def test_refresh_proves_guest_before_any_remote_git_operation() -> None:
    script = read("scripts/Refresh-SasOperatorCommand.ps1")
    for marker in (
        "NETWORK REQUIRED: GUEST / INTERNET",
        "$preRefreshNetwork = Get-SasOperatorNetworkClassification",
        "SAS_REFRESH_REMOTE_GIT_BLOCKED",
        "No remote Git operation was started",
        "PASS: Guest/Internet proved before remote repository maintenance.",
    ):
        assert marker in script, marker
    gate = script.index("$preRefreshNetwork = Get-SasOperatorNetworkClassification")
    reject = script.index("SAS_REFRESH_REMOTE_GIT_BLOCKED")
    clone = script.index("@('clone','--origin','origin'")
    fetch = script.index("@('fetch','--no-tags','--prune','origin'")
    assert gate < reject < clone < fetch


def test_refresh_uses_dedicated_guest_sync_cache_not_bootstrap_checkout_for_remote_git() -> None:
    script = read("scripts/Refresh-SasOperatorCommand.ps1")
    for marker in (
        "$syncCache = Join-Path $operatorStateRoot 'sync-cache'",
        "Creating Guest-only SysAdminSuite sync cache",
        "Refreshing Guest-only sync cache",
        "Unexpected sync-cache origin",
        "Guest sync cache contains local work. Nothing was reset or cleaned",
        "worktree','add','--detach',$fieldReady,$remoteHead",
    ):
        assert marker in script, marker
    assert "-C $RepositoryRoot fetch" not in script
    assert "-C $RepositoryRoot ls-remote" not in script
    assert "reset --hard" not in script
    assert "clean -fd" not in script


def test_refresh_defaults_field_runtime_to_main_but_allows_explicit_ref() -> None:
    script = read("scripts/Refresh-SasOperatorCommand.ps1")
    assert "$refreshBranch = if ([string]::IsNullOrWhiteSpace($Ref)) { 'main' } else { $Ref.Trim() }" in script
    assert "$remoteDisplay = \"origin/$refreshBranch\"" in script
    assert "check-ref-format','--branch',$refreshBranch" in script
    assert "Set-Content -LiteralPath $persistedRefPath -Value $refreshBranch" in script


def test_refresh_stages_sealed_c_sasal_before_installed_launcher_refresh() -> None:
    script = read("scripts/Refresh-SasOperatorCommand.ps1")
    for marker in (
        "scripts\\Prepare-SasAutoLogonShortRuntime.ps1",
        "STAGING SHORT AUTOLOGON RUNTIME BEFORE LEAVING GUEST",
        "-SourceRoot $fieldReady -RuntimeRoot 'C:\\SASAL' -ExpectedCommit $head",
        "Short AutoLogon runtime: C:\\SASAL",
        "Protected-side Git network I/O: DISABLED",
        "SAS_OPERATOR_REFRESH_READY",
    ):
        assert marker in script, marker
    recheck = script.index("Guest/Internet posture changed during refresh")
    stage = script.index("STAGING SHORT AUTOLOGON RUNTIME BEFORE LEAVING GUEST")
    install = script.index("$installer = Join-Path $fieldReady")
    ready = script.index("SAS_OPERATOR_REFRESH_READY")
    assert recheck < stage < install < ready


def test_refresh_requires_complete_autologon_runtime_surface() -> None:
    script = read("scripts/Refresh-SasOperatorCommand.ps1")
    for marker in (
        "Bootstrap-SysAdminSuiteAutoLogon.cmd",
        "Bootstrap-SysAdminSuiteAutoLogon.ps1",
        "scripts\\Prepare-SasAutoLogonShortRuntime.ps1",
        "scripts\\SasPortableLauncher.ps1",
        "scripts\\SasOperatorSession.psm1",
        "scripts\\SasAutoLogonOperatorState.psm1",
        "scripts\\SasTargetNameResolution.psm1",
        "scripts\\Invoke-SasAutoLogonOnsite.ps1",
        "scripts\\Invoke-SasAutoLogonFieldDeployment.ps1",
        "scripts\\Invoke-SasAutoLogonS4URestartDeployment.ps1",
        "scripts\\Invoke-SasAutoLogonKerberosS4UPilot.ps1",
        "scripts\\Recover-SasLatestInterruptedAutoLogonS4U.ps1",
    ):
        assert marker in script, marker


def test_installed_launcher_routes_remote_autologon_to_sealed_runtime_before_repo_discovery() -> None:
    launcher = read("scripts/SasPortableLauncher.ps1")
    for marker in (
        "sas refresh",
        "autologon-short-runtime.json",
        "Resolve-SasPreparedAutoLogonRuntime",
        "sas autologon Remote HOST",
        "sas-autologon-short-runtime/v2",
        "Protected-side Git activity: NONE",
        "& $runtime.bootstrap $target $runtime.commit",
    ):
        assert marker in launcher, marker
    dispatch = launcher.index("if ($normalized -eq 'autologon' -and $actualCommandArgs.Count -eq 2)")
    remote = launcher.index("& $runtime.bootstrap $target $runtime.commit")
    recover = launcher.index("& $recoveryLauncher 'Recover' $target")
    repo_discovery = launcher.index("$repoRoot = Resolve-SasRepoRoot")
    refresh_case = launcher.index("'refresh' {")
    autologon_case = launcher.index("'autologon' {")
    cybernet_case = launcher.index("'cybernet' {")
    assert dispatch < remote < repo_discovery
    assert dispatch < recover < repo_discovery
    assert refresh_case < autologon_case < cybernet_case


def test_refresh_surfaces_contain_no_target_contact_or_live_operator_literals() -> None:
    combined = "\n".join(
        read(path)
        for path in (
            "scripts/Refresh-SasOperatorCommand.ps1",
            "scripts/Prepare-SasAutoLogonShortRuntime.ps1",
            "scripts/SasPortableLauncher.ps1",
            "scripts/Install-SasPortableLauncher.ps1",
        )
    )
    lowered = combined.lower()
    for forbidden in (
        "pa_rperez26",
        "wpj075opr046",
        "rperez26@",
        "defaultpassword",
        "invoke-command",
        "schtasks.exe",
        "shutdown.exe",
    ):
        assert forbidden not in lowered, forbidden


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: sas operator refresh contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
