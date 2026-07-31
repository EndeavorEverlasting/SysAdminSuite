#!/usr/bin/env python3
"""Static contracts for guest-safe, branch-preserving operator refresh and stale-launcher recovery."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(relative: str) -> str:
    path = ROOT / relative
    assert path.is_file(), f"missing refresh surface: {relative}"
    return path.read_text(encoding="utf-8-sig")


def test_repo_local_refresh_surface_exists_and_is_guest_safe() -> None:
    cmd = read("Refresh-SasOperatorCommand.cmd")
    script = read("scripts/Refresh-SasOperatorCommand.ps1")
    assert "%~dp0" in cmd
    assert "Refresh-SasOperatorCommand.ps1" in cmd
    assert "SAS_OPERATOR_REFRESH_READY" in script
    assert "Existing source worktree was not reset or cleaned." in script
    assert "NETWORK REQUIRED: GUEST / INTERNET" in script
    for forbidden in (
        "Test-NetConnection",
        "schtasks.exe",
        "shutdown.exe",
        "Invoke-Command",
        "WinRM",
        "ADMIN$",
        "Probe-CybernetSoftware.cmd' -Arguments",
    ):
        assert forbidden.lower() not in script.lower(), forbidden


def test_refresh_preserves_active_branch_and_detached_remote_provenance() -> None:
    script = read("scripts/Refresh-SasOperatorCommand.ps1")
    for marker in (
        "Resolve-SasRefreshBranch",
        "branch --show-current",
        "branch -r --points-at HEAD",
        "origin/",
        "refs/heads/${refreshBranch}:${remoteTrackingRef}",
        "$remoteDisplay=\"origin/$refreshBranch\"",
        "worktree add --detach $fieldReady $remoteDisplay",
        "checkout --detach $remoteDisplay",
        "repo_ref=$refreshBranch",
        "REF: $refreshBranch",
    ):
        assert marker in script, marker

    # Old / detached checkouts may fall back to main, but a feature checkout must never be
    # unconditionally replaced with origin/main.
    assert "$candidate='main'" in script
    assert "fetch --prune origin main" not in script
    assert "worktree add --detach $fieldReady origin/main" not in script
    assert "checkout --detach origin/main" not in script


def test_refresh_never_force_updates_branch_provenance() -> None:
    script = read("scripts/Refresh-SasOperatorCommand.ps1")
    assert "Do not force-update the remote-tracking ref" in script
    assert 'fetch --prune origin "refs/heads/${refreshBranch}:${remoteTrackingRef}"' in script
    assert '"+refs/heads/' not in script
    assert "reset --hard" not in script
    assert "clean -fd" not in script


def test_installed_shim_self_refreshes_dispatcher_from_cached_repo() -> None:
    installer = read("scripts/Install-SasPortableLauncher.ps1")
    for marker in (
        "repo-root.txt",
        "SasPortableLauncher.ps1",
        "Get-FileHash -Algorithm SHA256",
        "Copy-Item -LiteralPath $s -Destination $d -Force",
        "sas launcher refreshed from cached SysAdminSuite repo.",
        "preserving installed launcher",
    ):
        assert marker in installer, marker
    assert "ParseFile($s" in installer
    assert "parse errors" in installer.lower()


def test_launcher_exposes_refresh_before_live_target_work() -> None:
    launcher = read("scripts/SasPortableLauncher.ps1")
    assert "sas refresh" in launcher
    assert "GUEST-SAFE" in launcher
    assert "On Guest/Internet: sas refresh" in launcher
    assert "Move to the approved protected network." in launcher
    assert "sas cybernet Deploy HOST" in launcher
    refresh_case = launcher.index("'refresh' {")
    evidence_case = launcher.index("'evidence' {")
    cybernet_case = launcher.index("'cybernet' {")
    assert refresh_case < evidence_case < cybernet_case
    assert "Refresh-SasOperatorCommand.ps1" in launcher


def test_refresh_requires_current_deployment_recovery_and_network_return_entrypoints() -> None:
    script = read("scripts/Refresh-SasOperatorCommand.ps1")
    for marker in (
        "Install-SasOperatorCommand.cmd",
        "Switch-Back-To-Previous-Network.cmd",
        "scripts\\Install-SasPortableLauncher.ps1",
        "scripts\\SasPortableLauncher.ps1",
        "scripts\\Return-SasOperatorToPreviousNetwork.ps1",
        "Find-SasEvidence.cmd",
        "Deploy-CybernetSoftware.cmd",
        "Probe-CybernetSoftware.cmd",
    ):
        assert marker in script, marker


def test_no_user_or_live_target_literals() -> None:
    combined = "\n".join(
        read(path)
        for path in (
            "Refresh-SasOperatorCommand.cmd",
            "scripts/Refresh-SasOperatorCommand.ps1",
            "scripts/Install-SasPortableLauncher.ps1",
            "scripts/SasPortableLauncher.ps1",
            "Switch-Back-To-Previous-Network.cmd",
            "scripts/Return-SasOperatorToPreviousNetwork.ps1",
        )
    )
    for forbidden in ("pa_rperez26", "WPJ075OPR046", "rperez26@", "rperez@"):
        assert forbidden.lower() not in combined.lower(), forbidden


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: sas operator refresh contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
