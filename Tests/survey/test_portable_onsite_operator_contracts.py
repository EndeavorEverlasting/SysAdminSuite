#!/usr/bin/env python3
"""Dependency-free contracts for the portable on-site operator surface.

These tests inspect tracked launcher and safety boundaries only. They do not connect
Wi-Fi, contact a target, mutate a target, install software, or change AutoLogon state.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(relative: str) -> str:
    path = ROOT / relative
    assert path.is_file(), f"missing operator surface file: {path}"
    return path.read_text(encoding="utf-8")


def test_auto_logon_onsite_launcher_is_repo_relative_and_bootstraps_local_request() -> None:
    cmd = read("Run-AutoLogonOnsite.cmd")
    script = read("scripts/Invoke-SasAutoLogonOnsite.ps1")
    assert "%~dp0" in cmd
    assert "Invoke-SasAutoLogonOnsite.ps1" in cmd
    assert "autologon-system-qualification-request.example.json" in script
    assert "survey\\input\\autologon-system-qualification" in script
    assert "qualification-request.local.json" in script
    assert "Copy-Item -LiteralPath $templatePath" in script
    assert "No live or validation action was started." in script
    assert script.count("@(Get-SasQualificationRequests)") >= 2


def test_guest_safe_actions_do_not_require_target_network() -> None:
    script = read("scripts/Invoke-SasAutoLogonOnsite.ps1")
    assert "qualification request (guest-safe)" in script
    assert "qualification request (guest-safe; no target contact)" in script
    assert "& $qualificationScript -Action Plan" in script
    pilot = script.index("'Pilot' {")
    interactive = script.index("'Interactive' {")
    live = script.index("& $qualificationScript -Action Live")
    interactive_live = script.index("& $interactiveScript -ComputerName $target")
    assert pilot < live
    assert interactive < interactive_live
    assert "Confirm-SasNorthwellNetwork.ps1" in script


def test_auto_logon_interactive_command_accepts_action_and_target() -> None:
    cmd = read("Run-AutoLogonOnsite.cmd")
    launcher = read("scripts/SasPortableLauncher.ps1")
    script = read("scripts/Invoke-SasAutoLogonOnsite.ps1")
    assert 'if not "%~3"==""' in cmd
    assert '-ComputerName "%~2"' in cmd
    assert "'Interactive'" in script
    assert "Invoke-SasAutoLogonInteractivePilot.ps1" in script
    assert "sas autologon Interactive HOST" in launcher


def test_network_guard_has_windows11_wifi_profile_fallback() -> None:
    guard = read("scripts/SasNetworkGuard.psm1")
    for marker in (
        "Get-SasWifiSsidFromConnectionProfiles",
        "Get-NetConnectionProfile -ErrorAction Stop",
        "InterfaceAlias",
        "wi-?fi|wireless|wlan",
        "Test-SasNorthwellWifiSsid -Ssid $name",
    ):
        assert marker in guard
    netsh = guard.index("netsh wlan show interfaces")
    fallback = guard.index("Get-NetConnectionProfile -ErrorAction Stop")
    assert netsh < fallback


def test_network_gate_allows_confirmed_saved_profile_switch_numeric_or_letter_choices() -> None:
    gate = read("scripts/Confirm-SasNorthwellNetwork.ps1")
    for marker in (
        "ENVIRONMENT_BLOCKED_GUEST_NETWORK",
        "[1/S] Switch to a saved approved Northwell Wi-Fi profile",
        "[2/R] I switched networks manually - recheck now",
        "[3/W] Open Windows Wi-Fi settings, then recheck",
        "[Q/C] Cancel this target operation",
        "'1' { $choice = 'S' }",
        "'2' { $choice = 'R' }",
        "'3' { $choice = 'W' }",
        "'Q' { $choice = 'C' }",
        "Type SWITCH to connect using the saved profile",
        "& netsh wlan connect name=\"$profile\"",
        "Test-SasNorthwellWifiSsid -Ssid $name",
        "ms-settings:network-wifi",
        "exit 1223",
        "target_contact_performed = $false",
        "target_mutation_performed = $false",
    ):
        assert marker in gate
    for forbidden in (
        "netsh wlan add profile",
        "netsh wlan set profileparameter",
        "Set-NetConnectionProfile",
        "New-NetIPAddress",
        "rasdial",
        "password=",
        "keymaterial",
    ):
        assert forbidden.lower() not in gate.lower()


def test_cybernet_target_operations_are_gated_in_engine_for_cmd_and_csv_paths() -> None:
    launcher = read("Run-CybernetBatchConfiguration.cmd")
    engine = read("Hardware/Cybernet/Invoke-CybernetBatchConfiguration.ps1")
    assert "Invoke-CybernetBatchConfiguration.ps1" in launcher
    assert "-Mode Apply" in launcher
    assert "-Mode Validate" in launcher
    assert "Confirm-SasNorthwellNetwork.ps1" in engine
    assert "$Mode -ne 'Plan' -and -not $FixtureMode" in engine
    assert "Cybernet $Mode batch canceled or blocked by the network gate before target contact" in engine
    assert "exit $gateExit" in engine


def test_portable_sas_command_discovers_and_caches_repo_without_username_literals() -> None:
    launcher = read("scripts/SasPortableLauncher.ps1")
    installer = read("scripts/Install-SasPortableLauncher.ps1")
    install_cmd = read("Install-SasOperatorCommand.cmd")
    for marker in (
        "$env:SAS_REPO_ROOT",
        "repo-root.txt",
        "$env:USERPROFILE",
        "$env:OneDrive",
        "OG Laptop Backup\\Desktop\\dev\\SysAdminSuite",
        "Run-AutoLogonOnsite.cmd",
        "Run-CybernetBatchConfiguration.cmd",
        "'autologon'",
        "'cybernet'",
        "'network'",
    ):
        assert marker in launcher
    assert "pa_rperez26" not in launcher
    assert "pa_rperez26" not in installer
    assert "%LOCALAPPDATA%" not in installer
    assert "$env:LOCALAPPDATA" in installer
    assert "SetEnvironmentVariable('Path'" in installer
    assert "'User'" in installer
    assert "%~dp0" in install_cmd


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: portable on-site operator contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
