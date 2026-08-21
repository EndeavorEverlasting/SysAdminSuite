#!/usr/bin/env python3
"""Static contracts for cross-user AutoLogon operator readiness.

No network, target contact, deployment, ACL mutation, or Windows runtime mutation occurs here.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

INSTALL_CMD = ROOT / "Install-AutoLogonOperatorReadiness.cmd"
INSTALLER = ROOT / "scripts" / "Install-SasAutoLogonOperatorReadiness.ps1"
VERIFIER = ROOT / "scripts" / "Test-SasAutoLogonOperatorReadiness.ps1"
DESKTOP_DELEGATE = ROOT / "scripts" / "SasAutoLogonPublicDesktop.cmd"
WORKFLOW = ROOT / ".github" / "workflows" / "autologon-operator-readiness.yml"
DOC = ROOT / "docs" / "AUTOLOGON_OPERATOR_READINESS.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def main() -> None:
    install_cmd = read(INSTALL_CMD)
    installer = read(INSTALLER)
    verifier = read(VERIFIER)
    desktop_delegate = read(DESKTOP_DELEGATE)
    workflow = read(WORKFLOW)
    doc = read(DOC)

    assert "Install-SasAutoLogonOperatorReadiness.ps1" in install_cmd
    assert "-RequireStandardUser" in install_cmd

    for marker in (
        "WindowsBuiltInRole]::Administrator",
        "AUTOLOGON_OPERATOR_READINESS_ADMIN_REQUIRED",
        "SysAdminSuite\\bin",
        "C:\\SASAL",
        "$runRoot = Join-Path $runtimeRoot 'runs'",
        "Machine",
        "S-1-5-32-545",
        "Invoke-SasIcacls -Path $runtimeRoot -Grant '*S-1-5-32-545:(OI)(CI)(RX)'",
        "Invoke-SasIcacls -Path $runRoot -Grant '*S-1-5-32-545:(OI)(CI)(M)'",
        "CommonDesktopDirectory",
        "CommonDocuments",
        "Test-SasAutoLogonOperatorReadiness.ps1",
        "SysAdminSuite - AutoLogon Remote.cmd",
        "SasAutoLogonPublicDesktop.cmd",
        "Copy-Item -LiteralPath $sourceDesktopDelegate -Destination $canonicalDesktopDelegate -Force",
        "Copy-Item -LiteralPath $canonicalDesktopDelegate -Destination $desktopCmdPath -Force",
        "receipt is evidence only",
    ):
        assert marker.lower() in installer.lower(), marker
    assert "Invoke-SasIcacls -Path $runtimeRoot -Grant '*S-1-5-32-545:(OI)(CI)(M)'" not in installer

    # Public Desktop entrypoint is one tracked canonical delegate, copied unchanged to ProgramData and Public Desktop.
    for marker in (
        'set "SAS_AUTOLOGON_ENTRYPOINT=%ProgramData%\\SysAdminSuite\\bin\\Invoke-SasNetworkAwareField.ps1"',
        'set /p "SAS_AUTOLOGON_TARGET=',
        "$env:SAS_AUTOLOGON_TARGET",
        "& $env:SAS_AUTOLOGON_ENTRYPOINT 'autologon' 'Remote' $t",
    ):
        assert marker in desktop_delegate, marker
    for forbidden in ("%~1", "-Confirm:$false", "Get-Credential", "Invoke-SasAutoLogonCrashSafeFieldRun.ps1", "Run-AutoLogonOnsite.cmd"):
        assert forbidden not in desktop_delegate, forbidden

    for marker in (
        "[switch]$RequireStandardUser",
        "WindowsBuiltInRole]::Administrator",
        "$localAdministratorsSid = 'S-1-5-32-544'",
        "$isLocalAdministratorMember",
        "LOCAL_ADMINISTRATOR_ACCOUNT_NOT_ALLOWED",
        "GetEnvironmentVariable('Path','Machine')",
        "Get-Command sas.cmd",
        "& $sasCmd platform",
        "$runRoot = Join-Path $RuntimeRoot 'runs'",
        "SAS_AUTOLOGON_OPERATOR_READINESS_WRITE_PROBE",
        "AUTOLOGON_RUN_ROOT_WRITABLE",
        "deployment_run_root_write_probe_passed",
        "SysAdminSuite - AutoLogon Remote.cmd",
        "SasAutoLogonPublicDesktop.cmd",
        "function Get-SasSha256Hex",
        "Get-SasSha256Hex -LiteralPath $desktopCmdPath",
        "Get-SasSha256Hex -LiteralPath $canonicalDesktopDelegate",
        "PUBLIC_DESKTOP_DELEGATE_VERIFIED",
        "Exact SHA-256 match to canonical installed delegate",
        "Resolve-SasAutoLogonManifestAuthority.ps1",
        "-RequireManifest",
        ".git\\sas-autologon-short-runtime.json",
        "Test-SasAutoLogonRuntimeSeal.ps1",
        "AUTOLOGON_RUNTIME_SEAL_VERIFIED",
        "sas-autologon-operator-readiness/v1",
        "AUTOLOGON_OPERATOR_READINESS_VERIFIED",
        "current_account_is_local_administrator_member",
        "receipt_is_authority = $false",
        "network_activity_performed = $false",
        "target_contact_performed = $false",
        "target_mutation_performed = $false",
        "deployment_started = $false",
        "autologon-operator-readiness.json",
        "autologon-runtime-seal-verification.json",
    ):
        assert marker in verifier, marker

    for forbidden in (
        "Get-Credential",
        "ConvertTo-SecureString",
        "Password=",
        "-Confirm:$false",
        "WPJ075",
        "nslijhs.net",
    ):
        assert forbidden.lower() not in (installer + desktop_delegate + install_cmd + doc).lower(), forbidden

    for marker in (
        "python Tests/survey/test_autologon_operator_readiness_contracts.py",
        "Windows PowerShell 5.1",
        "Install-SasAutoLogonOperatorReadiness.ps1",
        "Test-SasAutoLogonOperatorReadiness.ps1",
        "scripts/SasAutoLogonPublicDesktop.cmd",
        "github.event_name",
        "HEAD^...HEAD",
        "git diff --check",
    ):
        assert marker in workflow, marker

    for marker in (
        "C:\\Users\\Public\\Documents\\SysAdminSuite",
        "C:\\SASAL\\runs",
        "SysAdminSuite - AutoLogon Remote.cmd",
        "AUTOLOGON_OPERATOR_READINESS_VERIFIED",
        "repository/CI",
        "true standard-user",
        "does not deploy",
    ):
        assert marker.lower() in doc.lower(), marker

    print("PASS: AutoLogon operator-readiness contracts")


if __name__ == "__main__":
    main()
