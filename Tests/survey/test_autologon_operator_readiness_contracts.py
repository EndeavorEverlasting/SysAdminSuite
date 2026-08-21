#!/usr/bin/env python3
"""Static contracts for cross-user AutoLogon operator readiness.

No network, target contact, deployment, ACL mutation, or Windows runtime mutation occurs here.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

INSTALL_CMD = ROOT / "Install-AutoLogonOperatorReadiness.cmd"
INSTALLER = ROOT / "scripts" / "Install-SasAutoLogonOperatorReadiness.ps1"
VERIFIER = ROOT / "scripts" / "Test-SasAutoLogonOperatorReadiness.ps1"
WORKFLOW = ROOT / ".github" / "workflows" / "autologon-operator-readiness.yml"
DOC = ROOT / "docs" / "AUTOLOGON_OPERATOR_READINESS.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def main() -> None:
    install_cmd = read(INSTALL_CMD)
    installer = read(INSTALLER)
    verifier = read(VERIFIER)
    workflow = read(WORKFLOW)
    doc = read(DOC)

    assert "Install-SasAutoLogonOperatorReadiness.ps1" in install_cmd
    assert "-RequireStandardUser" in install_cmd

    for marker in (
        "WindowsBuiltInRole]::Administrator",
        "AUTOLOGON_OPERATOR_READINESS_ADMIN_REQUIRED",
        "SysAdminSuite\\bin",
        "C:\\SASAL",
        "Machine",
        "S-1-5-32-545",
        "CommonDesktopDirectory",
        "CommonDocuments",
        "Test-SasAutoLogonOperatorReadiness.ps1",
        "SysAdminSuite - AutoLogon Remote.cmd",
        "Invoke-SasNetworkAwareField.ps1",
        "set /p \"SAS_AUTOLOGON_TARGET=",
        "$env:SAS_AUTOLOGON_TARGET",
        "'autologon' 'Remote'",
        "receipt is evidence only",
    ):
        assert marker.lower() in installer.lower(), marker

    # Public Desktop entrypoint must delegate, never implement a second AutoLogon transaction.
    desktop = installer.split("$desktopCmd = @'", 1)[1].split("\n'@", 1)[0]
    assert "%~1" not in desktop
    assert "-Confirm:$false" not in desktop
    assert "Get-Credential" not in desktop
    assert "Invoke-SasAutoLogonCrashSafeFieldRun.ps1" not in desktop
    assert "Run-AutoLogonOnsite.cmd" not in desktop
    assert "SAS_AUTOLOGON_ENTRYPOINT" in desktop
    assert "Invoke-SasNetworkAwareField.ps1" in desktop
    assert "$env:SAS_AUTOLOGON_TARGET" in desktop

    for marker in (
        "[switch]$RequireStandardUser",
        "WindowsBuiltInRole]::Administrator",
        "GetEnvironmentVariable('Path','Machine')",
        "Get-Command sas.cmd",
        "& $sasCmd platform",
        "SysAdminSuite - AutoLogon Remote.cmd",
        "Resolve-SasAutoLogonManifestAuthority.ps1",
        "-RequireManifest",
        ".git\\sas-autologon-short-runtime.json",
        "Test-SasAutoLogonRuntimeSeal.ps1",
        "AUTOLOGON_RUNTIME_SEAL_VERIFIED",
        "sas-autologon-operator-readiness/v1",
        "AUTOLOGON_OPERATOR_READINESS_VERIFIED",
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
        assert forbidden.lower() not in (installer + verifier + install_cmd + doc).lower(), forbidden

    for marker in (
        "python Tests/survey/test_autologon_operator_readiness_contracts.py",
        "Windows PowerShell 5.1",
        "Install-SasAutoLogonOperatorReadiness.ps1",
        "Test-SasAutoLogonOperatorReadiness.ps1",
        "git diff --check",
    ):
        assert marker in workflow, marker

    for marker in (
        "C:\\Users\\Public\\Documents\\SysAdminSuite",
        "SysAdminSuite - AutoLogon Remote.cmd",
        "AUTOLOGON_OPERATOR_READINESS_VERIFIED",
        "repository/CI",
        "standard-user",
        "does not deploy",
    ):
        assert marker.lower() in doc.lower(), marker

    print("PASS: AutoLogon operator-readiness contracts")


if __name__ == "__main__":
    main()
