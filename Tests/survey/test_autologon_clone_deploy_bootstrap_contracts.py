#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Bootstrap-SysAdminSuiteAutoLogon.ps1"


def read() -> str:
    assert SCRIPT.is_file(), f"missing required file: {SCRIPT.relative_to(ROOT)}"
    return SCRIPT.read_text(encoding="utf-8-sig")


def test_short_runtime_and_exact_main_pin() -> None:
    text = read()
    assert "[string]$RuntimeRoot = 'C:\\SASAL'" in text
    assert "refs/heads/main:refs/remotes/origin/main" in text
    assert "@('checkout','--detach',$head)" in text
    assert "Short-runtime HEAD mismatch after checkout" in text


def test_git_executable_is_resolved_explicitly() -> None:
    text = read()
    assert "Resolve-SasGitExecutable" in text
    assert "Get-Command git.exe" in text
    assert "$script:SasGitExe" in text
    assert "(git exit $exitCode)" in text


def test_runtime_clone_and_origin_validation() -> None:
    text = read()
    assert "@('clone','--origin','origin',$RepoUrl,$RuntimeRoot)" in text
    assert "https://github.com/EndeavorEverlasting/SysAdminSuite.git" in text
    assert "Refusing unexpected SysAdminSuite origin" in text


def test_existing_runtime_is_preserved() -> None:
    text = read()
    assert "preserving it and validating ownership" in text
    assert "status','--porcelain" in text
    assert "will not be reset or cleaned" in text
    assert "reset --hard" not in text
    assert "clean -fd" not in text


def test_legacy_checkout_is_fallback_not_execution_authority() -> None:
    text = read()
    assert "Resolve-SasLegacyEvidenceRoot" in text
    assert "[Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)" in text
    assert "$env:SAS_REPO_ROOT = $legacyRoot" in text
    assert "$env:SAS_NETWORK_GUARD_CONFIG = $legacyNetworkConfig" in text


def test_canonical_network_guard_replaces_old_bootstrap_guard() -> None:
    text = read()
    assert "Confirm-SasNorthwellNetwork.ps1" in text
    assert "Enable-SasNorthwellVpnNetworkGuard.ps1" not in text
    assert "does not grant network authority" in text


def test_crash_safe_runner_and_parser_gate() -> None:
    text = read()
    assert "Invoke-SasAutoLogonCrashSafeFieldRun.ps1" in text
    assert "-RepositoryRoot $RuntimeRoot -ConfirmDeployment" in text
    assert "last-autologon-field-run.json" in text
    assert "System.Management.Automation.Language.Parser" in text
    assert "field-proof-worktrees" not in text


def test_no_live_target_or_secret_literal() -> None:
    text = read().lower()
    for forbidden in ("wpj075", "nslijhs.net", "defaultpassword", "password="):
        assert forbidden not in text, forbidden


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: AutoLogon runtime-first bootstrap contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
