#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AUDIT = ROOT / "scripts" / "Test-SasAutoLogonRuntimeSeal.ps1"
BOOTSTRAP_CMD = ROOT / "Bootstrap-SysAdminSuiteAutoLogon.cmd"
WINDOWS_FIXTURE = ROOT / "Tests" / "PowerShell" / "AutoLogonRuntimeSealAudit.Tests.ps1"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_audit_is_full_set_git_free_and_pre_transaction() -> None:
    text = read(AUDIT)
    for marker in (
        "sas-autologon-short-runtime/v2",
        "foreach ($entry in $sealEntries)",
        "HASH_MISMATCH",
        "MISSING_FILE",
        "AUTOLOGON_RUNTIME_SEAL_MISMATCH",
        "autologon-runtime-verification.json",
        "issue_count = $issues.Count",
        "changed_file_count = $changedCount",
        "missing_file_count = $missingCount",
        "checked_file_count = $checkedCount",
        "verified_file_count = $verifiedCount",
        "network_activity_performed = $false",
        "target_contact_performed = $false",
        "target_mutation_performed = $false",
        "crash_safe_run_started = $false",
        "No crash-safe AutoLogon field transaction was started.",
        "[Security.Cryptography.SHA256]::Create()",
    ):
        assert marker in text, marker
    assert "Get-FileHash" not in text
    for forbidden in (
        "& git",
        "git.exe",
        "Resolve-SasGitExecutable",
        "Invoke-SasLocalGit",
        "Get-SasLocalGitScalar",
        "rev-parse",
        "status --porcelain",
        "ls-remote",
    ):
        assert forbidden.lower() not in text.lower(), forbidden


def test_front_door_audits_before_bootstrap_and_propagates_failure() -> None:
    text = read(BOOTSTRAP_CMD)
    for marker in (
        "Test-SasAutoLogonRuntimeSeal.ps1",
        "FULL SEALED RUNTIME AUDIT - NO TARGET CONTACT",
        "SAS_AUDIT_RC",
        "Deployment blocked before crash-safe field transaction.",
        "SEALED RUNTIME AUDIT PASSED - ENTERING PROTECTED BOOTSTRAP",
    ):
        assert marker in text, marker
    audit_call = text.index('-File "%SAS_AUDIT%"')
    bootstrap_call = text.index('-File "%SAS_BOOTSTRAP%"')
    assert audit_call < bootstrap_call
    failure_gate = text.index('if not "%SAS_AUDIT_RC%"=="0"')
    assert audit_call < failure_gate < bootstrap_call
    assert "exit /b %SAS_AUDIT_RC%" in text


def test_windows_fixture_executes_multi_drift_and_pass_cases() -> None:
    text = read(WINDOWS_FIXTURE)
    for marker in (
        "Expected seal mismatch exit 10",
        "issue_count -ne 2",
        "changed_file_count -ne 2",
        "scripts/one.ps1,scripts/two.ps1",
        "HASH_MISMATCH",
        "crash_safe_run_started",
        "Expected seal audit success",
        "AUTOLOGON_RUNTIME_SEAL_VERIFIED",
    ):
        assert marker in text, marker
    assert "Get-FileHash" in text  # fixture explicitly proves the production audit never depends on it


def test_no_live_target_operator_or_secret_literal() -> None:
    combined = "\n".join(read(path) for path in (AUDIT, BOOTSTRAP_CMD, WINDOWS_FIXTURE)).lower()
    for forbidden in (
        "wpj075",
        "nslijhs.net",
        "pa_rperez26",
        "cheeksmcclappeth",
        "defaultpassword",
        "password=",
    ):
        assert forbidden not in combined, forbidden


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: AutoLogon runtime seal audit contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
