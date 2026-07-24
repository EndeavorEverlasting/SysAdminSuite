#!/usr/bin/env python3
"""Static contracts for the remote Kerberos/S4U AutoLogon pilot lane."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "Invoke-SasAutoLogonKerberosS4UPilot.ps1"
ONSITE = ROOT / "scripts" / "Invoke-SasAutoLogonOnsite.ps1"
CMD = ROOT / "Run-AutoLogonOnsite.cmd"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def test_s4u_requires_no_target_login_or_password() -> None:
    text = read(SCRIPT)
    for marker in (
        "'/RU',$PrincipalName,'/NP'",
        "'/RL','HIGHEST'",
        "logon_type = 'S4U'",
        "target_user_session_required = $false",
        "password_stored = $false",
        "password_supplied_or_stored = $false",
        "network_access_from_task_expected = $false",
        "Target login required: No",
    ):
        assert marker in text, marker
    assert "InteractiveToken" not in text
    assert "No logged-on user session" not in text
    assert "'/RP'" not in text.upper()


def test_current_controller_identity_is_kerberos_and_target_authorized() -> None:
    text = read(SCRIPT)
    for marker in (
        "Get-SasS4UOperatorIdentity",
        "identity.tgt_present",
        "service_tickets.cifs.issued",
        "service_tickets.host.issued",
        "admin_share.authorized",
        "scheduled_task_query.succeeded",
        "Request-SasS4UKerberosTicket",
        'CIFS/{0}',
        "KERBEROS_S4U_KERBEROS_IDENTITY_BLOCKED",
        "KERBEROS_S4U_SOFTWARE_SOURCE_KERBEROS_BLOCKED",
    ):
        assert marker in text, marker


def test_s4u_task_principal_is_current_named_domain_identity_and_elevated() -> None:
    text = read(SCRIPT)
    for marker in (
        "WindowsIdentity]::GetCurrent()",
        "S4U AutoLogon requires a domain identity",
        "expected_sid",
        "identity_matches_expected_sid",
        "WindowsBuiltInRole]::Administrator",
        "KERBEROS_S4U_PRINCIPAL_NOT_ELEVATED",
        "'/Create','/S',$Target",
        "'/RU',$PrincipalName,'/NP'",
        "'/Run','/S',$Target",
        "'/Delete','/S',$Target",
        "'/Query','/S',$Target",
    ):
        assert marker in text, marker


def test_package_is_staged_locally_before_s4u_install() -> None:
    text = read(SCRIPT)
    source_hash = text.index("Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256")
    stage = text.index("Copy-Item -LiteralPath $sourcePath -Destination $remoteInstallerUnc")
    target_hash = text.index("Get-FileHash -LiteralPath $remoteInstallerUnc -Algorithm SHA256")
    probe = text.index("Invoke-SasS4UTask -Target $resolvedTarget -TaskName $probeTask")
    install = text.index("Invoke-SasS4UTask -Target $resolvedTarget -TaskName $installTask")
    assert source_hash < stage < target_hash < probe < install
    assert "installer_arguments = @()" in text
    assert "installer_arguments_policy -ne 'approved_empty'" in text
    assert "network_access_from_task_expected = $false" in text


def test_final_gate_and_system_state_proof_surround_s4u_installer() -> None:
    text = read(SCRIPT)
    baseline = text.index("Invoke-SasAutoLogonSmbStateCapture -ComputerName $resolvedTarget -RunId $stateRunId -Phase baseline")
    gate = text.index("& $finalGateScript -Target $resolvedTarget")
    install = text.index("Invoke-SasS4UTask -Target $resolvedTarget -TaskName $installTask")
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


def test_system_failure_is_preserved_not_reclassified() -> None:
    text = read(SCRIPT)
    assert "canonical_system_qualification_changed = $false" in text
    assert "canonical_system_install_enabled" in text
    assert "canonical_system_qualification_status" in text
    assert "QUALIFIED_FOR_CANONICAL_SYSTEM" not in text
    assert "KERBEROS_S4U_AUTOLOGON_CONFIGURED_REBOOT_PROOF_PENDING" in text


def test_password_and_autologon_secret_data_are_not_collected() -> None:
    text = read(SCRIPT).lower()
    assert "default_password_value_collected = $false" in text
    assert "password_supplied_or_stored = $false" in text
    for forbidden in (
        "get-credential",
        "pscredential",
        "securestring",
        "'/rp'",
        '"/rp"',
        "defaultpassword).",
        "getvalue('defaultpassword'",
    ):
        assert forbidden not in text, forbidden


def test_operator_surface_routes_remote_action() -> None:
    onsite = read(ONSITE)
    cmd = read(CMD)
    assert "'Remote','S4U'" in onsite
    assert "Invoke-SasAutoLogonKerberosS4UPilot.ps1" in onsite
    assert "-ComputerName $target" in onsite
    assert "Remote AutoLogon via Kerberos SMB + passwordless S4U admin task" in onsite
    assert 'Run-AutoLogonOnsite.cmd Remote HOST' in cmd


def test_fixture_makes_no_live_claim() -> None:
    text = read(SCRIPT)
    for marker in (
        "KERBEROS_S4U_FIXTURE_READY",
        "target_mutation_performed = $false",
        "network_activity_performed = $false",
        "automatic_reboot_performed = $false",
        "automatic_sign_in_observed = $false",
        "canonical_system_qualification_changed = $false",
        "sanitized_fixture_contract",
    ):
        assert marker in text


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: AutoLogon Kerberos S4U contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
