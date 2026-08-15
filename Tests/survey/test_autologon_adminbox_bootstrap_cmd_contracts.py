#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "Bootstrap-SysAdminSuiteAutoLogon.cmd"
BOOTSTRAP = ROOT / "Bootstrap-SysAdminSuiteAutoLogon.ps1"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required launcher: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_launcher_forces_windows_powershell_51() -> None:
    text = read(LAUNCHER).lower()
    assert "%systemroot%\\system32\\windowspowershell\\v1.0\\powershell.exe" in text
    assert "pwsh.exe" not in text
    assert "engine:  windows powershell 5.1" in text


def test_launcher_is_protected_local_only_and_delegates_authorization() -> None:
    text = read(LAUNCHER)
    assert "Bootstrap-SysAdminSuiteAutoLogon.ps1" in text
    assert '-RuntimeRoot "%SAS_RUNTIME%"' in text
    assert "-ConfirmVpnPosture" in text
    assert "-ConfirmLocalTargetAuthorization" in text
    assert '-ExpectedCommit "%SAS_EXPECTED%"' in text
    assert "EXPECTED_PREPARED_COMMIT" in text
    assert "runtime must already be sealed by sas refresh on Guest/Internet" in text
    assert "Git network activity: NONE" in text
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

    runtime = text.index("PROTECTED AUTOLOGON RUNTIME VERIFICATION")
    network = text.index("PROVING NETWORK BEFORE CANONICAL TARGET AUTHORIZATION")
    resolution = text.index("Resolve-SasCanonicalTargetFqdn -TargetName $ComputerName")
    authorization = text.index("& $hostAuthorizer -Target $resolvedAuthorizationTarget")
    transaction = text.index("PRE-STAGED RUNTIME VERIFIED - STARTING CRASH-SAFE AUTOLOGON FIELD TRANSACTION")
    assert runtime < network < resolution < authorization < transaction


def test_legacy_policy_or_checkout_is_not_external_launcher_precondition() -> None:
    launcher = read(LAUNCHER)
    bootstrap = read(BOOTSTRAP)
    assert "host-eligibility-policy.local.json" not in launcher
    assert "Required operator-local host eligibility policy is missing" not in launcher
    assert "Required operator-local host eligibility policy is missing" not in bootstrap
    assert "LegacyEvidenceRoot" in bootstrap
    assert "Legacy evidence fallback: disabled." in bootstrap
    assert "GetFolderPath" not in bootstrap


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
