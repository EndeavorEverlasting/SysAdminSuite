#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Invoke-SasCredentialedApprovedSoftwareInstall.ps1"
CMD = ROOT / "Deploy-ApprovedSoftwareCredentialed.cmd"
CATALOG = ROOT / "configs" / "software-packages" / "approved-apps.json"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_runtime_only_credential_contract() -> None:
    text = read(SCRIPT)
    assert "[System.Management.Automation.PSCredential]$Credential" in text
    assert "Get-Credential" in text
    assert "New-PSSession -ComputerName $target -Credential $Credential -Authentication Negotiate" in text
    assert "credential_persisted = $false" in text
    forbidden = (
        "Export-Clixml",
        "ConvertFrom-SecureString",
        "ConvertTo-SecureString",
        "SecureStringToBSTR",
        "NetworkCredential).Password",
        "GetNetworkCredential().Password",
    )
    for marker in forbidden:
        assert marker not in text, marker


def test_no_uac_lua_or_winrm_policy_mutation() -> None:
    text = read(SCRIPT)
    for marker in (
        "EnableLUA",
        "LocalAccountTokenFilterPolicy",
        "TrustedHosts",
        "Set-WSManInstance",
        "Enable-PSRemoting",
        "Set-NetFirewallRule",
    ):
        # The comments may name the forbidden posture; executable mutation must not appear.
        executable = [line for line in text.splitlines() if not line.lstrip().startswith(("#", "."))]
        assert not any(marker in line and "never changes" not in line for line in executable), marker
    assert "administrator_token" in text
    assert "Refusing to alter UAC/LUA or token-filter policy" in text


def test_copy_then_install_avoids_second_hop() -> None:
    text = read(SCRIPT)
    assert "Copy-Item -LiteralPath $installerPath -Destination $remoteInstaller -ToSession $session -Force" in text
    assert "Get-FileHash -LiteralPath $installerPath -Algorithm SHA256" in text
    assert "target installer SHA-256 mismatch" in text.lower()
    assert "Start-Process -FilePath $filePath" in text
    assert "SoftwareShareRoot" not in "".join(
        line for line in text.splitlines() if "Invoke-Command -Session" in line
    )


def test_existing_safety_authorities_are_reused() -> None:
    text = read(SCRIPT)
    for marker in (
        "Confirm-SasNorthwellNetwork.ps1",
        "Test-SasHostEligibility.ps1",
        "SasTargetNameResolution.psm1",
        "approved-apps.json",
        "sas-harness-api.json",
        "Resolve-SasCanonicalTargetFqdn",
        "-ExecContext remote",
        "credentialed_winrm_install_enabled",
        "credentialed_winrm_qualification_enabled",
        "QualificationOnly is intentionally limited to exactly one target",
    ):
        assert marker in text, marker


def test_autologon_password_value_is_never_collected() -> None:
    text = read(SCRIPT)
    assert "GetValueNames()" in text
    assert "default_password_value_name_present" in text
    assert "GetValue('DefaultPassword'" not in text


def test_crash_diagnostics_survive_operator_shell_loss() -> None:
    text = read(SCRIPT)
    assert "last-credentialed-winrm-run.json" in text
    assert "credentialed_winrm_events.jsonl" in text
    assert "credentialed_winrm_result.json" in text
    assert "finally" in text
    assert "Remove-PSSession" in text
    assert "Remove-Variable Credential" in text


def test_catalog_requires_transport_specific_promotion() -> None:
    import json

    catalog = json.loads(read(CATALOG))
    packages = {row["id"]: row for row in catalog["packages"]}
    assert packages["bca"]["credentialed_winrm_install_enabled"] is True
    assert packages["autologon"]["credentialed_winrm_install_enabled"] is False
    assert packages["autologon"]["credentialed_winrm_qualification_enabled"] is True
    assert packages["allscripts-touchworks-22-1"]["credentialed_winrm_install_enabled"] is False


def test_cmd_front_door_keeps_terminal_visible() -> None:
    text = read(CMD)
    assert "Invoke-SasCredentialedApprovedSoftwareInstall.ps1" in text
    assert "-ConfirmDeployment" in text
    assert "pause" in text.lower()
    assert "last-credentialed-winrm-run.json" in text


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: credentialed WinRM approved software contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
