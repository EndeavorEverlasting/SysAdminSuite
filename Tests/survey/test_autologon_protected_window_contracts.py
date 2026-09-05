#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
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


def test_handoff_preserves_existing_protected_window() -> None:
    text = read(HANDOFF)
    for marker in (
        "Protected AutoLogon window fast path",
        "authenticated `DomainAuthenticated` VPN",
        "execute the sealed crash-safe AutoLogon front door **immediately from the existing protected posture**",
        "do not run `git fetch`",
        "do not run `sas refresh`",
        "fail quickly and preserve the network window",
        "setup-agnostic",
        "machine-wide universal `sas`",
        "current-user portable `sas`",
    ):
        require(text, marker, "operator handoff fast path")


def test_route_has_local_only_fast_path_before_refresh() -> None:
    text = read(ROUTE)
    fast = text.index("Protected-window fast path:")
    refresh = text.index("When the fast path is not applicable and the operator is on Guest/Internet")
    assert fast < refresh, "protected-window admission must be considered before refresh"
    for marker in (
        "do not run remote Git",
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
    assert "git " not in sealed_block.lower(), "portable protected lane must not invoke Git"


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
        "Tee-Object -FilePath $childOutputPath",
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
    test_handoff_preserves_existing_protected_window()
    test_route_has_local_only_fast_path_before_refresh()
    test_portable_remote_dispatch_precedes_repo_discovery()
    test_universal_route_accepts_all_protected_authorities_without_refresh()
    test_crash_safe_runner_owns_contiguous_progress()
    test_continuity_capability_and_compatibility_front_door_exist()
    print("PASS: AutoLogon protected-window fast path is setup-agnostic and progress-contiguous")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())