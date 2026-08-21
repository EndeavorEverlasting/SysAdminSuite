#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AUDIT = ROOT / "scripts" / "Test-SasAutoLogonRuntimeSeal.ps1"
RESOLVER = ROOT / "scripts" / "Resolve-SasAutoLogonManifestAuthority.ps1"
INSTALLER = ROOT / "scripts" / "Install-SasPortableLauncher.ps1"
BOOTSTRAP_CMD = ROOT / "Bootstrap-SysAdminSuiteAutoLogon.cmd"
WINDOWS_FIXTURE = ROOT / "Tests" / "PowerShell" / "AutoLogonRuntimeSealAudit.Tests.ps1"
AUTHORITY_FIXTURE = ROOT / "Tests" / "PowerShell" / "AutoLogonManifestAuthority.Tests.ps1"


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
        "SEAL_COUNT_INVALID",
        "[int]::TryParse($declaredSealCountText, [ref]$parsedSealCount)",
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
    assert "$declaredSealCount = [int]$declaredSealCountValue" not in text
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


def test_manifest_authority_survives_user_profile_changes_without_target_contact() -> None:
    text = read(RESOLVER)
    for marker in (
        ".git\\sas-autologon-short-runtime.json",
        "CURRENT_USER_LEGACY",
        "BOUNDED_PROFILE_LEGACY",
        "RUNTIME_LOCAL",
        "AUTOLOGON_MANIFEST_AUTHORITY_READY",
        "AUTOLOGON_MANIFEST_AMBIGUOUS",
        "AUTOLOGON_MANIFEST_NOT_FOUND",
        "runtime_authority_copy_written",
        "current_user_compatibility_copy_written",
        "tracked_runtime_mutation_performed = $false",
        "network_activity_performed = $false",
        "target_contact_performed = $false",
        "target_mutation_performed = $false",
        "Get-ChildItem -LiteralPath $LegacySearchRoot -Directory",
    ):
        assert marker in text, marker
    lowered = text.lower()
    for forbidden in (
        "& git",
        "git.exe",
        "invoke-command",
        "test-netconnection",
        "invoke-webrequest",
        "start-bitstransfer",
        "ls-remote",
    ):
        assert forbidden not in lowered, forbidden


def test_front_door_resolves_authority_then_audits_then_bootstraps() -> None:
    text = read(BOOTSTRAP_CMD)
    for marker in (
        "Resolve-SasAutoLogonManifestAuthority.ps1",
        "RESOLVING SEALED MANIFEST AUTHORITY - NO TARGET CONTACT",
        "SAS_MANIFEST_RC",
        "Test-SasAutoLogonRuntimeSeal.ps1",
        "FULL SEALED RUNTIME AUDIT - NO TARGET CONTACT",
        "SAS_AUDIT_RC",
        "Deployment blocked before crash-safe field transaction.",
        "SEALED RUNTIME AUDIT PASSED - ENTERING PROTECTED BOOTSTRAP",
    ):
        assert marker in text, marker
    resolver_call = text.index('-File "%SAS_MANIFEST_RESOLVER%"')
    audit_call = text.index('-File "%SAS_AUDIT%"')
    bootstrap_call = text.index('-File "%SAS_BOOTSTRAP%"')
    assert resolver_call < audit_call < bootstrap_call
    resolver_gate = text.index('if not "%SAS_MANIFEST_RC%"=="0"')
    failure_gate = text.index('if not "%SAS_AUDIT_RC%"=="0"')
    assert resolver_call < resolver_gate < audit_call < failure_gate < bootstrap_call
    assert "exit /b %SAS_MANIFEST_RC%" in text
    assert "exit /b %SAS_AUDIT_RC%" in text


def test_installed_sas_hydrates_authority_before_dispatch_and_after_refresh_install() -> None:
    text = read(INSTALLER)
    for marker in (
        "Resolve-SasAutoLogonManifestAuthority.ps1",
        "$manifestAuthoritySource",
        "$manifestAuthorityDestination",
        "Copy-Item -LiteralPath $manifestAuthoritySource -Destination $manifestAuthorityDestination -Force",
        'set "SAS_MANIFEST_RESOLVER=%~dp0Resolve-SasAutoLogonManifestAuthority.ps1"',
        '-File "%SAS_MANIFEST_RESOLVER%" -RuntimeRoot "C:\\SASAL"',
        "& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $manifestAuthorityDestination -RuntimeRoot 'C:\\SASAL'",
        "AutoLogon manifest authority is hydrated locally before dispatcher use",
    ):
        assert marker in text, marker
    cmd_resolver = text.index('-File "%SAS_MANIFEST_RESOLVER%"')
    launcher = text.index('-File "%SAS_INSTALLED%" %*')
    assert cmd_resolver < launcher


def test_windows_fixture_executes_multi_drift_malformed_and_pass_cases() -> None:
    text = read(WINDOWS_FIXTURE)
    for marker in (
        "Expected seal mismatch exit 10",
        "issue_count -ne 2",
        "changed_file_count -ne 2",
        "scripts/one.ps1,scripts/two.ps1",
        "HASH_MISMATCH",
        "crash_safe_run_started",
        "tracked_file_count = 'not-an-integer'",
        "Expected malformed seal count exit 10",
        "SEAL_COUNT_INVALID",
        "Malformed seal count did not write its durable receipt",
        "Expected seal audit success",
        "AUTOLOGON_RUNTIME_SEAL_VERIFIED",
    ):
        assert marker in text, marker
    assert "Get-FileHash" in text  # fixture explicitly proves the production audit never depends on it


def test_windows_authority_fixture_proves_migration_reuse_and_conflict_block() -> None:
    text = read(AUTHORITY_FIXTURE)
    for marker in (
        "BOUNDED_PROFILE_LEGACY",
        "Runtime-local authority copy was not created",
        "RUNTIME_LOCAL",
        "survive a simulated user-profile change",
        "Expected conflicting authorities to fail with exit 12",
        "AUTOLOGON_MANIFEST_AMBIGUOUS",
        "network_activity_performed",
        "target_contact_performed",
        "tracked_runtime_mutation_performed",
    ):
        assert marker in text, marker


def test_no_live_target_operator_or_secret_literal() -> None:
    combined = "\n".join(
        read(path) for path in (AUDIT, RESOLVER, INSTALLER, BOOTSTRAP_CMD, WINDOWS_FIXTURE, AUTHORITY_FIXTURE)
    ).lower()
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
