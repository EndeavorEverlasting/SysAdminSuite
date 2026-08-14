#!/usr/bin/env python3
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Invoke-SasCredentialedApprovedSoftwareInstall.ps1"
CMD = ROOT / "Deploy-ApprovedSoftwareCredentialed.cmd"
CATALOG = ROOT / "configs" / "software-packages" / "approved-apps.json"
DOC = ROOT / "docs" / "CREDENTIALED_WINRM_SOFTWARE_DEPLOYMENT.md"
PROFILE = ROOT / "Config" / "cybernet-client-preferences.json"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def test_runtime_only_credential_contract() -> None:
    text = read(SCRIPT)
    assert "[System.Management.Automation.PSCredential]$Credential" in text
    assert "Get-Credential" in text
    assert "New-PSSession -ComputerName $target -Credential $Credential -Authentication Negotiate" in text
    assert "credential_persisted = $false" in text
    for marker in (
        "Export-Clixml",
        "ConvertFrom-SecureString",
        "ConvertTo-SecureString",
        "SecureStringToBSTR",
        "GetNetworkCredential().Password",
    ):
        assert marker not in text, marker


def test_no_security_posture_weakening() -> None:
    text = read(SCRIPT)
    for marker in (
        "Set-WSManInstance",
        "Enable-PSRemoting",
        "Set-NetFirewallRule",
        "winrm set",
        "Set-Item WSMan:",
        "LocalAccountTokenFilterPolicy -Value",
        "EnableLUA -Value",
    ):
        assert marker not in text, marker
    assert "administrator_token" in text
    assert "Refusing to alter UAC/LUA or token-filter policy" in text


def test_independent_hash_pin_is_required_before_target_session() -> None:
    text = read(SCRIPT)
    pin_lookup = text.index("credentialed_winrm_expected_sha256")
    source_hash = text.index("Get-FileHash -LiteralPath $installerPath -Algorithm SHA256", pin_lookup)
    source_compare = text.index("Approved source SHA-256 mismatch", source_hash)
    credential = text.index("Get-Credential", source_compare)
    session = text.index("New-PSSession -ComputerName $target", credential)
    assert pin_lookup < source_hash < source_compare < credential < session
    assert "^[0-9a-f]{64}$" in text
    assert "Target installer SHA-256 mismatch" in text


def test_copy_through_session_avoids_second_hop() -> None:
    text = read(SCRIPT)
    assert "Copy-Item -LiteralPath $installerPath -Destination $remoteInstaller -ToSession $session -Force" in text
    assert "Get-FileHash -LiteralPath $Path -Algorithm SHA256" in text
    assert "Target installer SHA-256 mismatch" in text


def test_installer_arguments_cannot_override_catalog_policy() -> None:
    text = read(SCRIPT)
    assert "Test-SasStringArrayExact" in text
    assert "InstallerArguments override is not authorized" in text
    assert "exact catalog argument equality" in text
    assert "installer_arguments_policy" in text
    assert "approved_empty" in text


def test_autologon_requires_explicit_cybernet_profile_authority() -> None:
    text = read(SCRIPT)
    assert "[ValidateSet('Cybernet')]" in text
    assert "AutoLogon credentialed qualification requires explicit -EquipmentProfile Cybernet" in text
    assert "Config\\cybernet-client-preferences.json" in text
    assert "autologon_must_be_last" in text
    assert "final_separate_mutating_step" in text
    profile = json.loads(read(PROFILE))
    assert profile["profile_id"] == "cybernet-clinical-workstation-default"
    assert "autologon" in profile["software"]["package_ids"]
    assert profile["software"]["autologon_must_be_last"] is True


def test_staging_is_first_recorded_mutation() -> None:
    text = read(SCRIPT)
    stage = text.index("$stageRoot = Invoke-Command -Session $session")
    mutation = text.index("$result.target_mutation_performed = $true", stage)
    target_mutation = text.index("$targetResult.target_mutation_performed = $true", stage)
    copy = text.index("Copy-Item -LiteralPath $installerPath", stage)
    install = text.index("$targetResult.execution = Invoke-Command", copy)
    assert stage < mutation < copy < install
    assert stage < target_mutation < copy


def test_cleanup_failure_and_partial_completion_are_explicit() -> None:
    text = read(SCRIPT)
    assert "CREDENTIALED_WINRM_CLEANUP_REQUIRED" in text
    assert "do_not_retry_or_switch_transport_until_exact_run_cleanup_is_resolved" in text
    assert "CREDENTIALED_WINRM_PARTIAL_COMPLETION_REVIEW_REQUIRED" in text
    assert "preserve_completed_targets_and_select_any_retry_targets_explicitly" in text
    assert "completed_target_count" in text
    assert "failed_target_count" in text


def test_existing_authorities_are_reused() -> None:
    text = read(SCRIPT)
    for marker in (
        "Confirm-SasNorthwellNetwork.ps1",
        "Test-SasHostEligibility.ps1",
        "SasTargetNameResolution.psm1",
        "approved-apps.json",
        "sas-harness-api.json",
        "Resolve-SasCanonicalTargetFqdn",
        "-ExecContext remote",
    ):
        assert marker in text, marker


def test_autologon_password_value_is_never_collected() -> None:
    text = read(SCRIPT)
    assert "GetValueNames()" in text
    assert "default_password_value_name_present" in text
    assert "GetValue('DefaultPassword'" not in text


def test_crash_evidence_survives_operator_shell_loss() -> None:
    text = read(SCRIPT)
    assert "last-credentialed-winrm-run.json" in text
    assert "credentialed_winrm_events.jsonl" in text
    assert "credentialed_winrm_result.json" in text
    assert "finally" in text
    assert "Remove-PSSession" in text
    assert "Remove-Variable Credential" in text


def test_catalog_separates_transport_capability_from_package_promotion() -> None:
    catalog = json.loads(read(CATALOG))
    policy = catalog["catalog_policy"]
    packages = {row["id"]: row for row in catalog["packages"]}
    assert policy["credentialed_winrm_requires_explicit_package_opt_in"] is True
    assert policy["credentialed_winrm_requires_independently_pinned_sha256"] is True
    assert policy["credentialed_winrm_requires_exact_catalog_arguments"] is True
    for package in packages.values():
        assert "credentialed_winrm_expected_sha256" in package
    assert packages["bca"]["credentialed_winrm_install_enabled"] is False
    assert packages["bca"]["credentialed_winrm_expected_sha256"] is None
    assert packages["autologon"]["credentialed_winrm_install_enabled"] is False
    assert packages["autologon"]["credentialed_winrm_qualification_enabled"] is False
    assert packages["autologon"]["credentialed_winrm_expected_sha256"] is None
    assert packages["autologon"]["canonical_system_install_enabled"] is False
    assert packages["autologon"]["credentialed_winrm_qualification"]["equipment_profile"] == "Cybernet"


def test_cmd_front_door_supports_normal_and_qualification_modes() -> None:
    text = read(CMD)
    assert "Invoke-SasCredentialedApprovedSoftwareInstall.ps1" in text
    assert "-ConfirmDeployment" in text
    assert "QUALIFY" in text
    assert "-QualificationOnly -EquipmentProfile Cybernet" in text
    assert "pause" in text.lower()
    assert "last-credentialed-winrm-run.json" in text


def test_documentation_contains_no_live_target_identifier() -> None:
    text = read(DOC)
    assert "authorized-cybernet.example.invalid" in text
    forbidden_live_stems = ("wpj075opr046", "nslijhs.net")
    lowered = text.lower()
    for marker in forbidden_live_stems:
        assert marker not in lowered, marker


def test_transport_is_additive_not_replacement() -> None:
    doc = read(DOC)
    script = read(SCRIPT)
    assert "additional" in doc.lower()
    assert "never silently falls through" in doc
    assert "does not replace current-token WinRM" in script

    current_token = read(ROOT / "scripts" / "Invoke-SasSoftwareInstall.ps1")
    validated = read(ROOT / "scripts" / "Invoke-SasValidatedSoftwareDeployment.ps1")
    onsite = read(ROOT / "scripts" / "Invoke-SasAutoLogonOnsite.ps1")
    s4u = read(ROOT / "scripts" / "Invoke-SasAutoLogonKerberosS4UPilot.ps1")
    field = read(ROOT / "scripts" / "Invoke-SasAutoLogonFieldDeployment.ps1")

    assert "New-PSSession -ComputerName $target" in current_token
    assert "[ValidateSet('Auto', 'WinRM', 'SmbScheduledTask')]" in validated
    assert "Recover" in onsite and "Remote" in onsite
    assert "S4U" in s4u
    assert "autologon_field_deployment_result.json" in field
    assert "AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED" in field


def test_no_automatic_post_mutation_fallback() -> None:
    text = read(SCRIPT)
    assert "never performs automatic" in text
    assert "SMB scheduled-task" in text
    executable = re.sub(r"<#.*?#>", "", text, flags=re.S)
    assert "Invoke-SasSmbScheduledTaskDeployment" not in executable
    assert "Invoke-SasAutoLogonKerberosS4UPilot" not in executable


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: credentialed WinRM approved software contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
