#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "Bootstrap-SysAdminSuiteAutoLogon.cmd"
BOOTSTRAP = ROOT / "Bootstrap-SysAdminSuiteAutoLogon.ps1"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_launcher_forces_windows_powershell_51() -> None:
    text = read(LAUNCHER).lower()
    assert "%systemroot%\\system32\\windowspowershell\\v1.0\\powershell.exe" in text
    assert "pwsh.exe" not in text
    assert "engine:  windows powershell 5.1" in text


def test_launcher_delegates_network_and_target_authorization_to_canonical_bootstrap() -> None:
    text = read(LAUNCHER)
    assert "Bootstrap-SysAdminSuiteAutoLogon.ps1" in text
    assert '-RuntimeRoot "%SAS_RUNTIME%"' in text
    assert "-ConfirmVpnPosture" in text
    assert "-ConfirmLocalTargetAuthorization" in text
    assert '-ExpectedCommit "%SAS_EXPECTED%"' in text
    assert "git clone" not in text.lower()
    assert "git fetch" not in text.lower()
    assert "Set-SasHostEligibilityLocalTarget.ps1" not in text


def test_bootstrap_authorizes_resolved_fqdn_only_after_protected_network_admission() -> None:
    text = read(BOOTSTRAP)
    assert "[switch]$ConfirmLocalTargetAuthorization" in text
    assert "SasTargetNameResolution.psm1" in text
    assert "Set-SasHostEligibilityLocalTarget.ps1" in text
    assert "-ConfirmLocalAuthorization" in text
    assert "-Target $resolvedAuthorizationTarget" in text
    assert "-ExecContext remote" in text
    assert "@($authorizationResolution.addresses).Count -lt 1" in text
    assert "Canonical target authorized: $resolvedAuthorizationTarget" in text

    network = text.index("PROVING NETWORK BEFORE CANONICAL TARGET AUTHORIZATION")
    resolution = text.index("Resolve-SasCanonicalTargetFqdn -TargetName $ComputerName")
    authorization = text.index("& $hostAuthorizer -Target $resolvedAuthorizationTarget")
    transaction = text.index("STARTING CRASH-SAFE AUTOLOGON FIELD TRANSACTION")
    assert network < resolution < authorization < transaction


def test_missing_legacy_policy_is_not_an_external_launcher_precondition() -> None:
    launcher = read(LAUNCHER)
    bootstrap = read(BOOTSTRAP)
    assert "host-eligibility-policy.local.json" not in launcher
    assert "Required operator-local host eligibility policy is missing" not in launcher
    assert "Required operator-local host eligibility policy is missing" not in bootstrap
    assert "LegacyEvidenceRoot" in bootstrap


def test_launcher_propagates_bootstrap_exit_code() -> None:
    text = read(LAUNCHER)
    assert 'set "SAS_RC=%ERRORLEVEL%"' in text
    assert "exit /b %SAS_RC%" in text


def test_launcher_and_bootstrap_contain_no_live_target_secret_or_private_path() -> None:
    text = (read(LAUNCHER) + "\n" + read(BOOTSTRAP)).lower()
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
