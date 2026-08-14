#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "Bootstrap-SysAdminSuiteAutoLogon.cmd"


def read() -> str:
    assert LAUNCHER.is_file(), f"missing required launcher: {LAUNCHER.relative_to(ROOT)}"
    return LAUNCHER.read_text(encoding="utf-8-sig")


def test_launcher_forces_windows_powershell_51() -> None:
    text = read().lower()
    assert "%systemroot%\\system32\\windowspowershell\\v1.0\\powershell.exe" in text
    assert "pwsh.exe" not in text
    assert "engine:  windows powershell 5.1" in text


def test_launcher_delegates_to_canonical_bootstrap() -> None:
    text = read()
    assert "Bootstrap-SysAdminSuiteAutoLogon.ps1" in text
    assert '-RuntimeRoot "%SAS_RUNTIME%"' in text
    assert "-ConfirmVpnPosture" in text
    assert '-ExpectedCommit "%SAS_EXPECTED%"' in text
    assert "git clone" not in text.lower()
    assert "git fetch" not in text.lower()


def test_launcher_authorizes_exact_target_in_short_runtime() -> None:
    text = read()
    assert "Set-SasHostEligibilityLocalTarget.ps1" in text
    assert '-Target "%SAS_TARGET%"' in text
    assert "-ExecContext remote" in text
    assert '-RepoRoot "%SAS_RUNTIME%"' in text
    assert '-PolicyPath "%SAS_RUNTIME%\\Config\\%SAS_POLICY%"' in text
    assert "-ConfirmLocalAuthorization" in text
    assert "-PassThru" in text
    assert "Authorized exact target for remote execution" in text
    assert "regex = '.*'" not in text
    assert 'regex = ".*"' not in text


def test_launcher_treats_legacy_policy_as_optional_carryover() -> None:
    text = read()
    assert "host-eligibility-policy.local.json" in text
    assert '"%SAS_LEGACY%\\Config\\%SAS_POLICY%"' in text
    assert '"%SAS_RUNTIME%\\Config\\%SAS_POLICY%"' in text
    assert "Preserving existing short-runtime host eligibility policy" in text
    assert "A missing legacy policy is not a blocker" in text
    assert "sas-network-guard.local.json" not in text


def test_launcher_propagates_authorizer_and_bootstrap_exit_codes() -> None:
    text = read()
    assert 'set "SAS_AUTH_RC=%ERRORLEVEL%"' in text
    assert 'exit /b %SAS_AUTH_RC%' in text
    assert 'set "SAS_RC=%ERRORLEVEL%"' in text
    assert "exit /b %SAS_RC%" in text


def test_launcher_contains_no_live_target_secret_or_private_path() -> None:
    text = read().lower()
    for forbidden in (
        "wpj075",
        "nslijhs.net",
        "pa_rperez26",
        "one drive",
        "onedrive - northwell",
        "defaultpassword",
        "password=",
    ):
        assert forbidden not in text, forbidden


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: Admin Box AutoLogon bootstrap CMD contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
