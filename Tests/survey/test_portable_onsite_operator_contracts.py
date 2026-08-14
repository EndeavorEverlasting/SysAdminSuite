#!/usr/bin/env python3
"""Dependency-free contracts for the portable on-site operator surface.

These tests inspect tracked launcher and safety boundaries only. They do not connect
Wi-Fi, contact a target, mutate a target, install software, reboot a workstation, or
change AutoLogon state.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(relative: str) -> str:
    path = ROOT / relative
    assert path.is_file(), f"missing operator surface file: {path}"
    return path.read_text(encoding="utf-8-sig")


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


def test_local_system_candidate_actions_remain_separate_from_remote_s4u() -> None:
    script = read("scripts/Invoke-SasAutoLogonOnsite.ps1")
    assert "Validate LocalSystem qualification request (no target contact)" in script
    assert "& $qualificationScript -Action Plan" in script
    pilot = script.index("'Pilot' {")
    live = script.index("& $qualificationScript -Action Live")
    remote = script.index("{ $_ -in @('Remote','S4U') } {")
    deploy = script.index("& $fieldDeploymentScript -Action Remote -ComputerName $target")
    assert pilot < live
    assert remote < deploy
    assert "Confirm-SasNorthwellNetwork.ps1" in script


def test_auto_logon_remote_command_accepts_action_target_canonicalization_and_restart() -> None:
    cmd = read("Run-AutoLogonOnsite.cmd")
    launcher = read("scripts/SasPortableLauncher.ps1")
    onsite = read("scripts/Invoke-SasAutoLogonOnsite.ps1")
    field = read("scripts/Invoke-SasAutoLogonFieldDeployment.ps1")
    deployment = read("scripts/Invoke-SasAutoLogonS4URestartDeployment.ps1")
    assert 'if not "%~3"==""' in cmd
    assert '-ComputerName "%~2"' in cmd
    assert "'Remote','S4U'" in onsite
    assert "Invoke-SasAutoLogonFieldDeployment.ps1" in onsite
    assert "Resolve-SasCanonicalTargetFqdn -TargetName $requestedTarget" in field
    assert "Invoke-SasAutoLogonS4URestartDeployment.ps1" in field
    assert "sas autologon Remote HOST" in launcher
    assert "restart" in launcher.lower()
    assert "Invoke-SasAutoLogonKerberosS4UPilot.ps1" in deployment
    assert "AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED" in deployment
    assert "automatic_reboot_performed" in deployment
    assert "shutdown.exe /r /t" in deployment


def test_network_zero_argument_surface_filters_forwarded_empty_arguments() -> None:
    launcher = read("scripts/SasPortableLauncher.ps1")
    assert "function Get-SasActualArguments" in launcher
    assert "Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }" in launcher
    assert "$actualCommandArgs = Get-SasActualArguments -Arguments $CommandArgs" in launcher
    zero = launcher.index("if ($actualCommandArgs.Count -eq 0)")
    gate = launcher.index("Confirm-SasNorthwellNetwork.ps1", zero)
    one = launcher.index("if ($actualCommandArgs.Count -eq 1)", gate)
    assert zero < gate < one


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
    current_wifi = guard.index("function Get-SasCurrentWifiSsid {")
    netsh = guard.index("netsh wlan show interfaces", current_wifi)
    fallback = guard.index("Get-NetConnectionProfile -ErrorAction Stop", netsh)
    assert current_wifi < netsh < fallback


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
    assert "Cybernet $Mode batch canceled or blocked by the network gate" in engine
    assert "exit $gateExit" in engine


def test_portable_sas_cybernet_deploy_routes_to_full_profile_and_keeps_hardware_separate() -> None:
    launcher = read("scripts/SasPortableLauncher.ps1")
    cmd = read("Deploy-CybernetSoftware.cmd")
    orchestrator = read("scripts/Invoke-SasCybernetSoftwareDeployment.ps1")
    core = read("scripts/Invoke-SasCybernetClinicalCoreDeployment.ps1")
    assert "sas cybernet Deploy HOST" in launcher
    assert "Deploy-CybernetSoftware.cmd" in launcher
    assert "Run-CybernetBatchConfiguration.cmd" in launcher
    assert "Hardware-only Cybernet apply" in launcher
    assert "full Cybernet software profile" in launcher
    assert "-AllowTargetMutation -ConfirmDeployment" in cmd
    assert "Invoke-SasCybernetClinicalCoreDeployment.ps1" in orchestrator
    assert "Invoke-SasAutoLogonS4URestartDeployment.ps1" in orchestrator
    assert "AutoLogon must be the final software step" in orchestrator
    assert "CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED" in orchestrator
    assert "cybernet-clinical-core" in core
    assert "AutoLogon must not be part of the clinical-core deployment lane" in core


def test_technician_guidance_deploys_then_restarts_without_test_loop_requirement() -> None:
    launcher = read("scripts/SasPortableLauncher.ps1")
    start_here = read("START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md")
    tutorial = read("docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md")

    for text in (launcher, start_here, tutorial):
        assert "sas cybernet Deploy" in text
        assert "sas autologon Remote" in text
        assert "AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED" in text
        assert "restart" in text.lower()

    for text in (start_here, tutorial):
        lowered = text.lower()
        assert "autologon" in lowered
        assert "last" in lowered
        assert "automatic" in lowered and "restart" in lowered
        assert "not a prerequisite" in lowered or "not required" in lowered
        assert "fixture" in lowered and "live-cert" in lowered
        assert "technician" in lowered

    assert "CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED" in launcher


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
        "Deploy-CybernetSoftware.cmd",
        "Deploy-CybernetClinicalCore.cmd",
        "'autologon'",
        "'cybernet'",
        "'network'",
    ):
        assert marker in launcher
    assert "pa_rperez26" not in launcher.lower()
    assert "pa_rperez26" not in installer.lower()
    assert "%LOCALAPPDATA%" not in installer
    assert "$env:LOCALAPPDATA" in installer
    assert "SetEnvironmentVariable('Path'" in installer
    assert "'User'" in installer
    assert "%~dp0" in install_cmd


def test_installed_launcher_self_refresh_converges_without_get_file_hash() -> None:
    installer = read("scripts/Install-SasPortableLauncher.ps1")
    assert "Copy-Item -LiteralPath $s -Destination $d -Force" in installer
    assert "Parser]::ParseFile" in installer
    executable = installer.replace("No Get-FileHash dependency is used.", "").replace("without Get-FileHash", "")
    assert "Get-FileHash" not in executable
    assert "SasAutoLogonOperatorState.psm1" in installer
    assert "Invoke-SasAutoLogonFieldDeployment.ps1" in installer


def test_context_exposes_repo_branch_target_recovery_and_deployment_state() -> None:
    context = read("scripts/Show-SasOperatorContext.ps1")
    state = read("scripts/SasAutoLogonOperatorState.psm1")
    for marker in (
        "Branch/ref:",
        "Requested target:",
        "Canonical target FQDN:",
        "Historical S4U recovery:",
        "AutoLogon deployment started:",
        "AutoLogon deployment completed:",
        "NEXT NETWORK:",
        "NEXT COMMAND:",
    ):
        assert marker in context, marker
    assert "Sync-SasAutoLogonOperatorState" in context
    assert "autologon_field_deployment_result.json" in state
    assert "s4u_probe_hang_recovery_result.json" in state


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: portable on-site operator contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
