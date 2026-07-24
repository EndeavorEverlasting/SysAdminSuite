#!/usr/bin/env python3
"""Static contracts for the bounded AutoLogon InteractiveToken pilot lane."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Invoke-SasAutoLogonInteractivePilot.ps1"
ONSITE = ROOT / "scripts" / "Invoke-SasAutoLogonOnsite.ps1"
CMD = ROOT / "Run-AutoLogonOnsite.cmd"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def test_interactive_token_security_context_is_explicit() -> None:
    text = read(SCRIPT)
    for marker in (
        "LogonType = 3",
        "RunLevel = 1",
        "InteractiveToken",
        "HighestAvailable",
        "[Environment]::UserInteractive",
        "WindowsBuiltInRole]::Administrator",
        "identity_matches_expected",
        "No logged-on user session was captured",
        "INTERACTIVE_TOKEN_NOT_ELEVATED",
    ):
        assert marker in text, marker


def test_existing_system_failure_is_not_promoted_or_bypassed() -> None:
    text = read(SCRIPT)
    assert "canonical_system_qualification_changed = $false" in text
    assert "canonical_system_install_enabled" in text
    assert "Canonical SYSTEM qualification remains blocked and is not being bypassed." in text
    assert "INTERACTIVE_TOKEN_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING" in text
    assert "QUALIFIED_FOR_CANONICAL_SYSTEM" not in text


def test_final_step_and_state_proof_surround_installer_execution() -> None:
    text = read(SCRIPT)
    baseline = text.index("Invoke-SasAutoLogonSmbStateCapture -ComputerName $resolvedTarget -RunId $stateRunId -Phase baseline")
    gate = text.index("& $finalGateScript -Target $resolvedTarget")
    install = text.index("Invoke-SasInteractiveTask -Target $resolvedTarget -TaskName $installTask")
    after = text.index("Invoke-SasAutoLogonSmbStateCapture -ComputerName $resolvedTarget -RunId $stateRunId -Phase after")
    assert baseline < gate < install < after
    for marker in (
        "postinstall_set_autologon -eq 'Autologon_YES'",
        "auto_admin_logon -eq '1'",
        "default_password_present",
        "expected_user_match",
        "status -eq 'autologon_ready'",
    ):
        assert marker in text


def test_passwords_are_never_collected_or_passed() -> None:
    text = read(SCRIPT).lower()
    assert "default_password_value_collected = $false" in text
    assert "password_supplied_or_stored = $false" in text
    for forbidden in (
        "-credential",
        "get-credential",
        "securestring",
        "/rp",
        "smb_pass",
        "defaultpassword).",
        "getvalue('defaultpassword'",
    ):
        assert forbidden not in text, forbidden


def test_package_identity_is_catalog_and_hash_bound() -> None:
    text = read(SCRIPT)
    for marker in (
        "approved-apps.json",
        "harness\\api\\sas-harness-api.json",
        "installer_arguments_policy -ne 'approved_empty'",
        "Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256",
        "Get-FileHash -LiteralPath $remoteInstallerUnc -Algorithm SHA256",
        "source_target_hash_match",
    ):
        assert marker in text


def test_portable_operator_surface_routes_action_and_target() -> None:
    onsite = read(ONSITE)
    cmd = read(CMD)
    assert "'Interactive'" in onsite
    assert "Invoke-SasAutoLogonInteractivePilot.ps1" in onsite
    assert "-ComputerName $target" in onsite
    assert 'if not "%~3"==""' in cmd
    assert '-ComputerName "%~2"' in cmd


def test_fixture_has_no_live_claim() -> None:
    text = read(SCRIPT)
    for marker in (
        "INTERACTIVE_TOKEN_FIXTURE_READY",
        "target_mutation_performed = $false",
        "network_activity_performed = $false",
        "automatic_reboot_performed = $false",
        "automatic_sign_in_observed = $false",
        "sanitized_fixture_contract",
    ):
        assert marker in text


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: AutoLogon interactive-token contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
