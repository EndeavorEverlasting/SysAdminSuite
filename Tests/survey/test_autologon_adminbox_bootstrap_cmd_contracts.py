#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "Bootstrap-SysAdminSuiteAutoLogon.cmd"
BOOTSTRAP = ROOT / "Bootstrap-SysAdminSuiteAutoLogon.ps1"
ONSITE = ROOT / "scripts" / "Invoke-SasAutoLogonOnsite.ps1"
ELIGIBILITY = ROOT / "scripts" / "Test-SasHostEligibility.ps1"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required launcher: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_launcher_forces_windows_powershell_51() -> None:
    text = read(LAUNCHER).lower()
    assert "%systemroot%\\system32\\windowspowershell\\v1.0\\powershell.exe" in text
    assert "pwsh.exe" not in text
    assert "engine:  windows powershell 5.1" in text


def test_launcher_is_protected_local_only_and_explicit_target_is_authority() -> None:
    text = read(LAUNCHER)
    assert "Bootstrap-SysAdminSuiteAutoLogon.ps1" in text
    assert '-RuntimeRoot "%SAS_RUNTIME%"' in text
    assert "-ConfirmVpnPosture" in text
    assert "-ConfirmLocalTargetAuthorization" not in text
    assert 'set "SAS_EXPLICIT_REMOTE_TARGET_REQUEST=%SAS_TARGET%"' in text
    assert "Target authority: explicit one-target operator command" in text
    assert '-ExpectedCommit "%SAS_EXPECTED%"' in text
    assert "EXPECTED_PREPARED_COMMIT" in text
    assert "runtime must already be sealed by sas refresh on Guest/Internet" in text
    assert "Git network activity: NONE" in text
    assert "git clone" not in text.lower()
    assert "git fetch" not in text.lower()
    assert "Set-SasHostEligibilityLocalTarget.ps1" not in text


def test_direct_onsite_launcher_carries_exact_target_authority() -> None:
    text = read(ONSITE)
    assert "$Action -in @('Remote','S4U')" in text
    assert "$env:SAS_EXPLICIT_REMOTE_TARGET_REQUEST = $resolvedTarget" in text
    assert "Test-SasHostEligibility permits only" in text
    assert "localhost, different hosts, fixture/vm contexts" in text

    resolver = text.index("function Resolve-SasRemoteTarget")
    authority = text.index("$env:SAS_EXPLICIT_REMOTE_TARGET_REQUEST = $resolvedTarget", resolver)
    deployment = text.index("& $fieldDeploymentScript -Action Remote", authority)
    assert resolver < authority < deployment

    # Recover is cleanup-only and must not silently gain install/deploy authority from this marker.
    condition = text[text.rfind("if ($Action", resolver, authority):authority]
    assert "'Remote','S4U'" in condition
    assert "'Recover'" not in condition


def test_eligibility_gate_accepts_only_process_scoped_exact_remote_target() -> None:
    text = read(ELIGIBILITY)
    assert "SAS_EXPLICIT_REMOTE_TARGET_REQUEST" in text
    assert "Test-SasExplicitRemoteTargetRequest" in text
    assert "EXPLICIT_REMOTE_TARGET_AUTHORIZED" in text
    assert "operator-explicit-target" in text
    assert "$ExecContext -eq 'remote'" in text
    assert "$resolved.StartsWith(($requested + '.')" in text
    assert "LOCAL_FALLBACK_BLOCKED" in text
    assert "POLICY_FILE_MISSING" in text

    explicit = text.index("SAS_EXPLICIT_REMOTE_TARGET_REQUEST")
    missing_policy = text.index("POLICY_FILE_MISSING")
    assert explicit < missing_policy


def test_bootstrap_keeps_optional_legacy_policy_authorizer_out_of_standard_launcher() -> None:
    launcher = read(LAUNCHER)
    bootstrap = read(BOOTSTRAP)
    assert "[switch]$ConfirmLocalTargetAuthorization" in bootstrap
    assert "Set-SasHostEligibilityLocalTarget.ps1" in bootstrap
    assert "-ConfirmLocalTargetAuthorization" not in launcher


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
    text = (read(LAUNCHER) + "\n" + read(BOOTSTRAP) + "\n" + read(ONSITE)).lower()
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
