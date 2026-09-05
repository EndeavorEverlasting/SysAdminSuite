#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GOVERNANCE = ROOT / "AGENTS.md"
HANDOFF = ROOT / "harness/skills/operator-command-handoff/SKILL.md"
ROUTE = ROOT / "harness/skills/operator-execution-route/SKILL.md"
CRASH_SAFE = ROOT / "scripts/Invoke-SasAutoLogonCrashSafeFieldRun.ps1"
PORTABLE = ROOT / "scripts/SasPortableLauncher.ps1"
UNIVERSAL = ROOT / "scripts/Invoke-SasUniversalField.ps1"
PROGRESS = ROOT / "scripts/SasAutoLogonProgress.psm1"
COMPAT = ROOT / "Run-AutoLogon-ContiguousProgress.cmd"


def read(path: Path) -> str:
    assert path.is_file(), f"missing protected-window authority: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def require(text: str, marker: str, owner: str) -> None:
    assert marker in text, f"{owner} missing: {marker}"


def test_root_governance_bounds_the_exception() -> None:
    text = read(GOVERNANCE)
    for marker in (
        "Bounded sealed-runtime protected-window exception",
        "refreshed provider truth is still mandatory before handoff",
        "ancestor of the refreshed default head",
        "every currently required safety/capability fix",
        "not revoked by a current contract",
        "exact `prepared_commit`",
        "fail closed without changing the operator's current VPN/hardwire/WAB posture",
    ):
        require(text, marker, "root protected-window governance")


def test_handoff_preserves_existing_protected_window_without_skipping_provider_freshness() -> None:
    text = read(HANDOFF)
    for marker in (
        "Protected AutoLogon window fast path",
        "Provider-side refreshed remote truth remains mandatory before this fast path is handed to an operator.",
        "ancestor of the refreshed default head",
        "not revoked by a current contract",
        "authenticated `DomainAuthenticated` VPN",
        "execute the sealed crash-safe AutoLogon front door **immediately from the existing protected posture**",
        "do not run workstation `git fetch`",
        "do not run `sas refresh`",
        "fail quickly and preserve the network window",
        "setup-agnostic",
        "machine-wide universal `sas`",
        "current-user portable `sas`",
    ):
        require(text, marker, "operator handoff fast path")


def test_route_has_provider_fresh_floor_before_local_fast_path() -> None:
    text = read(ROUTE)
    provider = text.index("refresh provider/default-branch truth before handoff")
    fast = text.index("Protected-window fast path:")
    refresh = text.index("When the fast path is not applicable and the operator is on Guest/Internet")
    assert provider < fast < refresh, "provider freshness must precede local protected-window admission, which must precede workstation refresh"
    for marker in (
        "exact equality between `prepared_commit` and the provider-selected accepted immutable deployment floor",
        "do not run workstation remote Git",
        "do not invoke `sas refresh`",
        "do not disconnect/reconnect VPN",
        "Run-AutoLogon-ContiguousProgress.cmd",
        "SasAutoLogonProgress.psm1",
    ):
        require(text, marker, "operator execution fast path")


def test_portable_remote_dispatch_precedes_repo_discovery() -> None:
    text = read(PORTABLE)
    sealed_dispatch = text.index("if ($normalized -eq 'autologon' -and $actualCommandArgs.Count -eq 2)")
    repo_discovery = text.index("$repoRoot = Resolve-SasRepoRoot")
    assert sealed_dispatch < repo_discovery, "portable AutoLogon Remote must not require checkout discovery"
    sealed_block = text[sealed_dispatch:repo_discovery]
    require(sealed_block, "Protected-side Git activity: NONE", "portable protected lane")
    for forbidden in ("& git", "git.exe", "Invoke-SasRefreshGit", "Resolve-SasGitExecutable"):
        assert forbidden.lower() not in sealed_block.lower(), f"portable protected lane invokes Git through: {forbidden}"


def test_universal_route_accepts_all_protected_authorities_without_refresh() -> None:
    text = read(UNIVERSAL)
    require(text, "Supported protected paths: Northwell hardwire, NSLIJHS-WAB, authenticated DomainAuthenticated VPN.", "universal protected authorities")
    autologon = text.split("    'autologon' {", 1)[1].split("    'cybernet' {", 1)[0]
    require(autologon, "Assert-SasProtectedForAction", "universal AutoLogon protected gate")
    require(autologon, "Resolve-SasInstalledAutoLogonBootstrap", "universal AutoLogon bootstrap")
    assert "sas refresh" not in autologon.lower(), "universal protected AutoLogon must not refresh"


def test_crash_safe_runner_owns_contiguous_progress() -> None:
    text = read(CRASH_SAFE)
    for marker in (
        "SasAutoLogonProgress.psm1",
        "Import-Module $progressModule -Force",
        "ConvertTo-SasAutoLogonContiguousProgress",
        "Tee-Object -FilePath $childOutputPath -ErrorAction Stop",
        "$ErrorActionPreference = 'Continue'",
        "$result.child_exit_code = [int]$LASTEXITCODE",
    ):
        require(text, marker, "crash-safe continuity seam")
    assert text.index("ConvertTo-SasAutoLogonContiguousProgress") < text.index("Tee-Object -FilePath $childOutputPath"), "durable child output must contain normalized stages"


def test_continuity_capability_and_compatibility_front_door_exist() -> None:
    progress = read(PROGRESS)
    compat = read(COMPAT)
    require(progress, "SKIP - underlying path did not enter this stage", "progress module")
    require(compat, "--no-pause", "compatibility front door")
    require(compat, "AutoLogon command exit code", "compatibility front door")


def main() -> int:
    test_root_governance_bounds_the_exception()
    test_handoff_preserves_existing_protected_window_without_skipping_provider_freshness()
    test_route_has_provider_fresh_floor_before_local_fast_path()
    test_portable_remote_dispatch_precedes_repo_discovery()
    test_universal_route_accepts_all_protected_authorities_without_refresh()
    test_crash_safe_runner_owns_contiguous_progress()
    test_continuity_capability_and_compatibility_front_door_exist()
    print("PASS: AutoLogon protected-window fast path is provider-fresh, setup-agnostic, and progress-contiguous")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
