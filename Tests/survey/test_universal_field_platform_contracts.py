#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
PLATFORM = ROOT / 'scripts' / 'SasFieldPlatform.psm1'
LAUNCHER = ROOT / 'scripts' / 'Invoke-SasUniversalField.ps1'
INSTALLER = ROOT / 'scripts' / 'Install-SasUniversalFieldLauncher.ps1'
PRINTER_BOOTSTRAP = ROOT / 'Bootstrap-SysAdminSuitePrinter.ps1'
INSTALL_CMD = ROOT / 'Install-SasOperatorCommand.cmd'
DOC = ROOT / 'docs' / 'UNIVERSAL_FIELD_PLATFORM.md'


def read(path: Path) -> str:
    assert path.is_file(), f'missing {path.relative_to(ROOT)}'
    return path.read_text(encoding='utf-8')


def main() -> None:
    platform = read(PLATFORM)
    launcher = read(LAUNCHER)
    installer = read(INSTALLER)
    printer_bootstrap = read(PRINTER_BOOTSTRAP)
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

    # Resolve-SasControllerRoot intentionally starts with an empty List[string]. PowerShell 5.1 must
    # be allowed to bind that accumulator before the first runtime/repo candidate is considered.
    assert "[AllowEmptyCollection()][System.Collections.Generic.List[string]]$List" in platform

    # Controller authority is machine-local and must fail closed when locality cannot be proven.
    assert "Path -match '^(?:\\\\\\\\|//)'" in platform
    assert "return ($driveType -eq 3)" in platform
    assert "$driveType -eq 0 -or $driveType -eq 3" not in platform
    assert "Get-PSDrive -Name $driveName -PSProvider FileSystem" in platform
    assert "New-Object IO.DriveInfo" in platform
    assert "SysAdminSuite will not execute from a UNC share, mapped network drive, or target machine path" in platform

    # Cache writes are optimization only; read/execute-only machine installs cannot be bricked by them.
    assert "Cache persistence is an optimization only" in platform
    assert "Set-Content -LiteralPath $path" in platform
    assert "catch {" in platform

    # The universal front door handles protected actions before delegating compatibility commands.
    for marker in (
        'Assert-SasProtectedNetworkAuthority',
        "'refresh'",
        "'printer'",
        "'clipboard'",
        "'autologon'",
        "'cybernet'",
        'Bootstrap-SysAdminSuitePrinter.ps1',
        'Reset-SasClipboard.ps1',
        'Run-AutoLogonOnsite.cmd',
        'Confirm-SasNorthwellNetwork.ps1',
        '$env:SAS_RUNTIME_ROOT = $runtimeRoot',
        '$env:SAS_REPO_ROOT = $controllerRoot',
        '$actualArgs = @(',
        'LOCAL_MACHINE_ONLY',
    ):
        assert marker in launcher, marker
    assert '$args = @(' not in launcher

    # Printer mapping must be a feature, not a repository-path ritual. The installed trusted bootstrap
    # owns runtime discovery; quick mapping is the default and file/batch mapping is a pathless submode.
    printer_block = launcher.split("    'printer' {", 1)[1].split("\n    'clipboard' {", 1)[0]
    assert 'Resolve-SasInstalledPrinterBootstrap' in printer_block
    assert 'Map-NorthwellPrinter-SystemWide.cmd' not in printer_block
    assert 'Usage: sas printer [file]' in printer_block
    assert "$printerMode = 'Quick'" in printer_block
    assert "$printerMode = 'File'" in printer_block
    assert '-Mode $printerMode' in printer_block

    # The installer must carry the trusted bootstrap beside sas.cmd instead of depending on whichever
    # printer files happen to exist in a controller checkout.
    assert "$sourcePrinterBootstrap = Join-Path $repoRoot 'Bootstrap-SysAdminSuitePrinter.ps1'" in installer
    assert "$printerBootstrapDestination = Join-Path $installRoot 'Bootstrap-SysAdminSuitePrinter.ps1'" in installer
    assert 'Copy-Item -LiteralPath $sourcePrinterBootstrap -Destination $printerBootstrapDestination -Force' in installer

    # Bootstrap runtime cleanliness is scoped to the printer-owned execution surface. Unrelated field
    # hotfixes do not force a second runtime, while printer-owned edits still fail closed.
    assert "[ValidateSet('Quick','File')][string]$Mode = 'Quick'" in printer_bootstrap
    assert "Map-NorthwellPrinters-FromFile.cmd" in printer_bootstrap
    assert "mapping\\Start-NorthwellPrinterBatch.ps1" in printer_bootstrap
    assert "$statusArguments += @($script:requiredRuntimePaths)" in printer_bootstrap
    assert "@('status','--porcelain','--untracked-files=no','--')" in printer_bootstrap
    assert "$launcherName = if ($Mode -eq 'File')" in printer_bootstrap

    # Local clipboard recovery is intentionally outside the protected network gate.
    clipboard_block = launcher.split("    'clipboard' {", 1)[1].split("\n    'autologon' {", 1)[0]
    assert 'Assert-SasProtectedForAction' not in clipboard_block
    assert 'Usage: sas clipboard [reset]' in clipboard_block

    # `sas network HOST` retains the established one-target readiness probe instead of collapsing to
    # a local-only posture check.
    assert 'Network readiness probe for $($actualArgs[0])' in launcher
    assert 'Invoke-SasLegacyDispatcher' in launcher

    # Refresh may use the existing Guest-only synchronization implementation, but after sealing the
    # new C:\SASAL it must restore the universal machine-neutral command from that sealed runtime.
    assert "Refresh-SasOperatorCommand.ps1" in launcher
    assert "C:\\SASAL\\scripts\\Install-SasUniversalFieldLauncher.ps1" in launcher
    assert "UNIVERSAL_FIELD_PLATFORM_REFRESH_CONVERGED" in launcher

    # Canonical installation is machine-first. A current-user shim is allowed only when the canonical
    # machine runtime already exists; a user-profile checkout cannot become shared execution authority.
    assert "$machineRoot = if ($env:ProgramData)" in installer
    assert "CURRENT_USER_SHIM_WITH_MACHINE_RUNTIME" in installer
    assert "MACHINE_NEUTRAL_RUNTIME_REQUIRED" in installer
    assert "$repoIsUserScoped" in installer
    assert "Controller runtime distribution: LOCAL MACHINE ONLY" in installer
    assert 'Install-SasUniversalFieldLauncher.ps1' in install_cmd

    # The CMD shim must execute only the installer-owned PowerShell copy. SAS_RUNTIME_ROOT is handled
    # later by trusted PowerShell after local-controller validation.
    assert 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-SasUniversalField.ps1" %*' in installer
    assert 'if defined SAS_RUNTIME_ROOT' not in installer

    # No operator identity or one user's filesystem is allowed into the new platform surfaces.
    combined = '\n'.join((platform, launcher, installer, printer_bootstrap, install_cmd))
    for forbidden in (
        'pa_rperez26', 'CheeksMcClappeth', 'Cheex', 'Richard Perez',
        'Desktop\\dev\\SysAdminSuite', 'OG Laptop Backup',
    ):
        assert forbidden.lower() not in combined.lower(), forbidden

    # Runtime distribution boundary: no new platform surface constructs a target UNC path or copies
    # the SysAdminSuite controller tree to another machine.
    assert not re.search(r'Copy-Item[^\n]+\\\\\$?(?:target|computer|hostname)', combined, re.I)
    assert 'runtime is never copied to a target' in launcher

    for marker in (
        'hardwire', 'NSLIJHS-WAB', 'authenticated VPN',
        'machine-local', 'not copied to target machines',
        'username-specific path is not execution authority',
        'sas printer', 'sas clipboard',
    ):
        assert marker.lower() in doc.lower(), marker

    print('PASS: universal field platform contracts')


if __name__ == '__main__':
    main()
