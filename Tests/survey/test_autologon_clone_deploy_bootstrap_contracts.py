#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Bootstrap-SysAdminSuiteAutoLogon.ps1"


def read() -> str:
    assert SCRIPT.is_file(), f"missing required file: {SCRIPT.relative_to(ROOT)}"
    return SCRIPT.read_text(encoding="utf-8-sig")


def test_durable_checkout_uses_windows_desktop_known_folder() -> None:
    text = read()
    assert "[Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)" in text
    assert "Join-Path $desktop 'dev'" in text
    assert "'SysAdminSuite'" in text


def test_missing_checkout_clones_official_repo() -> None:
    text = read()
    assert "@('clone', '--origin', 'origin', $RepoUrl, $install)" in text
    assert "https://github.com/EndeavorEverlasting/SysAdminSuite.git" in text
    assert "Refusing to overwrite existing non-Git folder" in text


def test_existing_checkout_is_preserved() -> None:
    text = read()
    assert "preserving its branch and local work" in text
    assert "reset --hard" not in text
    assert "clean -fd" not in text
    assert "@('worktree', 'add', '--detach', $field, $head)" in text


def test_fetched_main_can_be_pinned() -> None:
    text = read()
    assert "refs/heads/main:refs/remotes/origin/main" in text
    assert "$ExpectedCommit" in text
    assert "origin/main changed" in text


def test_vpn_guard_precedes_crash_safe_deployment() -> None:
    text = read()
    vpn = text.index("Enable-SasNorthwellVpnNetworkGuard.ps1")
    launcher = text.index("Run-AutoLogonCrashSafe.cmd")
    assert vpn < launcher
    assert "-ConfirmVpnPosture" in text
    assert "SAS_NETWORK_GUARD_CONFIG" in text
    assert "& $launcher $ComputerName" in text


def test_parser_gate_and_durable_pointer_exist() -> None:
    text = read()
    assert "System.Management.Automation.Language.Parser" in text
    assert "last-autologon-field-run.json" in text
    assert "field-proof-worktrees" in text
    assert "exit $deploymentExit" in text


def test_no_live_target_or_secret_literal() -> None:
    text = read().lower()
    for forbidden in ("wpj075", "nslijhs.net", "defaultpassword", "password="):
        assert forbidden not in text, forbidden


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: AutoLogon clone-and-deploy bootstrap contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
