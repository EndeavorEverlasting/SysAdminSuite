#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
PLATFORM = ROOT / 'scripts' / 'SasFieldPlatform.psm1'
NETWORK_INTENT = ROOT / 'scripts' / 'SasNetworkIntent.psm1'
NETWORK_WRAPPER = ROOT / 'scripts' / 'Invoke-SasNetworkAwareField.ps1'
LAUNCHER = ROOT / 'scripts' / 'Invoke-SasUniversalField.ps1'
INSTALLER = ROOT / 'scripts' / 'Install-SasUniversalFieldLauncher.ps1'
PRINTER_BOOTSTRAP = ROOT / 'Bootstrap-SysAdminSuitePrinter.ps1'
AUTOLOGON_BOOTSTRAP_CMD = ROOT / 'Bootstrap-SysAdminSuiteAutoLogon.cmd'
AUTOLOGON_BOOTSTRAP_PS1 = ROOT / 'Bootstrap-SysAdminSuiteAutoLogon.ps1'
INSTALL_CMD = ROOT / 'Install-SasOperatorCommand.cmd'
DOC = ROOT / 'docs' / 'UNIVERSAL_FIELD_PLATFORM.md'


def read(path: Path) -> str:
    assert path.is_file(), f'missing {path.relative_to(ROOT)}'
    return path.read_text(encoding='utf-8')


def main() -> None:
    platform = read(PLATFORM)
    network_intent = read(NETWORK_INTENT)
    network_wrapper = read(NETWORK_WRAPPER)
    launcher = read(LAUNCHER)
    installer = read(INSTALLER)
    printer_bootstrap = read(PRINTER_BOOTSTRAP)
    autologon_bootstrap_cmd = read(AUTOLOGON_BOOTSTRAP_CMD)
    autologon_bootstrap_ps1 = read(AUTOLOGON_BOOTSTRAP_PS1)
    install_cmd = read(INSTALL_CMD)
    doc = read(DOC)

    for marker in (
        "authority = 'WAB_WIFI'",
        "'DOMAIN_AUTHENTICATED_WIRED'",
        "'DOMAIN_AUTHENTICATED_VPN'",
        "controller_runtime_scope = 'LOCAL_MACHINE_ONLY'",
        "Test-SasLocalControllerPath",
        "Resolve-SasExecutionRuntimeRoot",
        "No machine-local SysAdminSuite controller surface was found",
    ):
        assert marker in platform, marker

    assert "[AllowEmptyCollection()][System.Collections.Generic.List[string]]$List" in platform
    assert "Path -match '^(?:\\\\\\\\|//)'" in platform
    assert "return ($driveType -eq 3)" in platform
    assert "$driveType -eq 0 -or $driveType -eq 3" not in platform
    assert "Get-PSDrive -Name $driveName -PSProvider FileSystem" in platform
    assert "New-Object IO.DriveInfo" in platform
    assert "SysAdminSuite will not execute from a UNC share, mapped network drive, or target machine path" in platform
    assert "Cache persistence is an optimization only" in platform
    assert "Set-Content -LiteralPath $path" in platform
    assert "catch {" in platform

    # The installed shim now owns only command-level network intent/canary and bounded saved-WLAN
    # restoration. The existing universal dispatcher remains product authority underneath it.
    for marker in (
        "SasNetworkIntent.psm1",
        "Invoke-SasUniversalField.ps1",
        "'refresh'",
        "$intent = 'InternetSync'",
        "'printer'",
        "$intent = 'ProtectedNorthwell'",
        "'clipboard' { $intent = 'LocalOnly' }",
        "Enter-SasNetworkIntent",
        "Restore-SasNetworkIntent",
        "& powershell.exe @childArgs",
    ):
        assert marker in network_wrapper, marker
    assert network_wrapper.index('Enter-SasNetworkIntent') < network_wrapper.index('& powershell.exe @childArgs') < network_wrapper.index('Restore-SasNetworkIntent')

    for marker in (
        "NETWORK REQUIRED:",
        "CURRENT NETWORK:",
        "CURRENT AUTHORITY:",
        "AUTO-SWITCH:",
        "SAS_NETWORK_TRANSITION_MANUAL_VPN_REQUIRED",
        "SAS_NETWORK_RESTORE_FAILED",
        "SAVED_WLAN_PROFILE",
    ):
        assert marker in network_intent, marker

    for marker in (
        'Assert-SasProtectedNetworkAuthority', "'refresh'", "'printer'", "'clipboard'", "'autologon'", "'cybernet'",
        'Bootstrap-SysAdminSuitePrinter.ps1', 'Bootstrap-SysAdminSuiteAutoLogon.cmd', 'Reset-SasClipboard.ps1',
        'Run-AutoLogonOnsite.cmd', 'Confirm-SasNorthwellNetwork.ps1', '$env:SAS_RUNTIME_ROOT = $runtimeRoot',
        '$env:SAS_REPO_ROOT = $controllerRoot', '$actualArgs = @(', 'LOCAL_MACHINE_ONLY',
    ):
        assert marker in launcher, marker
    assert '$args = @(' not in launcher

    printer_block = launcher.split("    'printer' {", 1)[1].split("\n    'clipboard' {", 1)[0]
    assert 'Resolve-SasInstalledPrinterBootstrap' in printer_block
    assert 'Map-NorthwellPrinter-SystemWide.cmd' not in printer_block
    assert 'Usage: sas printer [file]' in printer_block
    assert "$printerMode = 'Quick'" in printer_block
    assert "$printerMode = 'File'" in printer_block
    assert "-RequiredCommit '66d38dd45881692303f77267e29e4fa44b4a9351'" in printer_block
    assert '-Mode $printerMode' in printer_block

    assert "$sourcePrinterBootstrap = Join-Path $repoRoot 'Bootstrap-SysAdminSuitePrinter.ps1'" in installer
    assert "$printerBootstrapDestination = Join-Path $installRoot 'Bootstrap-SysAdminSuitePrinter.ps1'" in installer
    assert 'Copy-Item -LiteralPath $sourcePrinterBootstrap -Destination $printerBootstrapDestination -Force' in installer
    assert "$sourceNetworkAwareLauncher = Join-Path $repoRoot 'scripts\\Invoke-SasNetworkAwareField.ps1'" in installer
    assert "$sourceNetworkIntent = Join-Path $repoRoot 'scripts\\SasNetworkIntent.psm1'" in installer
    assert 'Copy-Item -LiteralPath $sourceNetworkAwareLauncher -Destination $networkAwareLauncherDestination -Force' in installer
    assert 'Copy-Item -LiteralPath $sourceNetworkIntent -Destination $networkIntentDestination -Force' in installer

    # AutoLogon Remote is target-mutating and must always enter the sealed crash-safe bootstrap.
    # Recover remains recovery-only and is intentionally not converted into deployment.
    autologon_block = launcher.split("    'autologon' {", 1)[1].split("\n    'cybernet' {", 1)[0]
    for marker in (
        'Resolve-SasInstalledAutoLogonBootstrap',
        "Join-Path $runtimeRoot 'Bootstrap-SysAdminSuiteAutoLogon.cmd'",
        "if ($mode -eq 'remote')",
        '& $bootstrap $target',
        'durable field evidence REQUIRED',
        "Join-Path $runtimeRoot 'Run-AutoLogonOnsite.cmd'",
        '& $recoveryLauncher Recover $target',
    ):
        assert marker in launcher if marker.startswith('Resolve-SasInstalledAutoLogonBootstrap') or marker.startswith('Join-Path $runtimeRoot') else marker in autologon_block, marker
    assert '& $recoveryLauncher Remote $target' not in autologon_block
    assert '& $launcher $action $target' not in autologon_block

    assert 'Bootstrap-SysAdminSuiteAutoLogon.ps1' in autologon_bootstrap_cmd
    assert '-ConfirmVpnPosture' in autologon_bootstrap_cmd
    assert 'sas-autologon-short-runtime/v2' in autologon_bootstrap_ps1
    assert 'function Get-SasSha256Hex' in autologon_bootstrap_ps1
    assert '[Security.Cryptography.SHA256]::Create()' in autologon_bootstrap_ps1
    assert 'Get-FileHash' not in autologon_bootstrap_ps1
    assert 'Invoke-SasAutoLogonCrashSafeFieldRun.ps1' in autologon_bootstrap_ps1
    assert 'PRE-STAGED RUNTIME VERIFIED - STARTING CRASH-SAFE AUTOLOGON FIELD TRANSACTION' in autologon_bootstrap_ps1
    assert '-RepositoryRoot $RuntimeRoot -RepositoryHead $preparedCommit -ConfirmDeployment' in autologon_bootstrap_ps1
    assert 'last-autologon-field-run.json' in autologon_bootstrap_ps1

    assert "[string]$RequiredCommit = '66d38dd45881692303f77267e29e4fa44b4a9351'" in printer_bootstrap
    assert "[ValidateSet('Quick','File')][string]$Mode = 'Quick'" in printer_bootstrap
    for marker in (
        'mapping\\Confirm-NorthwellPrinterActiveUserMaterialization.ps1',
        'mapping\\Agents\\Invoke-NorthwellPrinterActiveUserAgent.ps1',
        'Map-NorthwellPrinters-FromFile.cmd',
        'mapping\\Start-NorthwellPrinterBatch.ps1',
    ):
        assert marker in printer_bootstrap, marker
    assert "$statusArguments += @($script:requiredRuntimePaths)" in printer_bootstrap
    assert "@('status','--porcelain','--untracked-files=no','--')" in printer_bootstrap
    assert "$launcherName = if ($Mode -eq 'File')" in printer_bootstrap

    clipboard_block = launcher.split("    'clipboard' {", 1)[1].split("\n    'autologon' {", 1)[0]
    assert 'Assert-SasProtectedForAction' not in clipboard_block
    assert 'Usage: sas clipboard [reset]' in clipboard_block

    assert 'Network readiness probe for $($actualArgs[0])' in launcher
    assert 'Invoke-SasLegacyDispatcher' in launcher
    assert "Refresh-SasOperatorCommand.ps1" in launcher
    assert "C:\\SASAL\\scripts\\Install-SasUniversalFieldLauncher.ps1" in launcher
    assert "UNIVERSAL_FIELD_PLATFORM_REFRESH_CONVERGED" in launcher

    assert "$machineRoot = if ($env:ProgramData)" in installer
    assert "CURRENT_USER_SHIM_WITH_MACHINE_RUNTIME" in installer
    assert "MACHINE_NEUTRAL_RUNTIME_REQUIRED" in installer
    assert "$repoIsUserScoped" in installer
    assert "Controller runtime distribution: LOCAL MACHINE ONLY" in installer
    assert 'Install-SasUniversalFieldLauncher.ps1' in install_cmd
    assert 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-SasNetworkAwareField.ps1" %*' in installer
    assert 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-SasUniversalField.ps1" %*' not in installer
    assert 'if defined SAS_RUNTIME_ROOT' not in installer

    combined = '\n'.join((platform, network_intent, network_wrapper, launcher, installer, printer_bootstrap, autologon_bootstrap_cmd, autologon_bootstrap_ps1, install_cmd))
    for forbidden in (
        'pa_rperez26', 'CheeksMcClappeth', 'Cheex', 'Richard Perez',
        'Desktop\\dev\\SysAdminSuite', 'OG Laptop Backup',
    ):
        assert forbidden.lower() not in combined.lower(), forbidden

    assert not re.search(r'Copy-Item[^\n]+\\\\\$?(?:target|computer|hostname)', combined, re.I)
    assert 'runtime is never copied to a target' in launcher

    for marker in (
        'hardwire', 'NSLIJHS-WAB', 'authenticated VPN', 'machine-local', 'not copied to target machines',
        'username-specific path is not execution authority', 'sas printer', 'sas clipboard',
        'NETWORK REQUIRED', 'automatic return', 'saved WLAN',
    ):
        assert marker.lower() in doc.lower(), marker

    print('PASS: universal field platform contracts')


if __name__ == '__main__':
    main()
