#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
PLATFORM = ROOT / 'scripts' / 'SasFieldPlatform.psm1'
LAUNCHER = ROOT / 'scripts' / 'Invoke-SasUniversalField.ps1'
INSTALLER = ROOT / 'scripts' / 'Install-SasUniversalFieldLauncher.ps1'
INSTALL_CMD = ROOT / 'Install-SasOperatorCommand.cmd'
DOC = ROOT / 'docs' / 'UNIVERSAL_FIELD_PLATFORM.md'


def read(path: Path) -> str:
    assert path.is_file(), f'missing {path.relative_to(ROOT)}'
    return path.read_text(encoding='utf-8')


def main() -> None:
    platform = read(PLATFORM)
    launcher = read(LAUNCHER)
    installer = read(INSTALLER)
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

    # Controller authority is machine-local: UNC and mapped-network runtimes are rejected.
    assert "Path -match '^(?:\\\\\\\\|//)'" in platform
    assert "$driveType -eq 0 -or $driveType -eq 3" in platform
    assert "SysAdminSuite will not execute from a UNC share, mapped network drive, or target machine path" in platform

    # The universal front door handles protected actions before delegating compatibility commands.
    for marker in (
        'Assert-SasProtectedNetworkAuthority',
        "'refresh'",
        "'printer'",
        "'autologon'",
        "'cybernet'",
        'Map-NorthwellPrinter-SystemWide.cmd',
        'Run-AutoLogonOnsite.cmd',
        'Confirm-SasNorthwellNetwork.ps1',
        '$env:SAS_RUNTIME_ROOT = $runtimeRoot',
        '$env:SAS_REPO_ROOT = $controllerRoot',
        '$actualArgs = @(',
        'LOCAL_MACHINE_ONLY',
    ):
        assert marker in launcher, marker
    assert '$args = @(' not in launcher

    # Refresh may use the existing Guest-only synchronization implementation, but after sealing the
    # new C:\SASAL it must restore the universal machine-neutral command from that sealed runtime.
    assert "Refresh-SasOperatorCommand.ps1" in launcher
    assert "C:\\SASAL\\scripts\\Install-SasUniversalFieldLauncher.ps1" in launcher
    assert "UNIVERSAL_FIELD_PLATFORM_REFRESH_CONVERGED" in launcher

    # Canonical installation is machine-first. Current-user installation is only a shim fallback,
    # never controller/runtime authority.
    assert "$machineRoot = if ($env:ProgramData)" in installer
    assert "CURRENT_USER_FALLBACK" in installer
    assert "C:\\SASAL\\scripts\\Invoke-SasUniversalField.ps1" in installer
    assert "Controller runtime distribution: LOCAL MACHINE ONLY" in installer
    assert 'Install-SasUniversalFieldLauncher.ps1' in install_cmd

    # No operator identity or one user's filesystem is allowed into the new platform surfaces.
    combined = '\n'.join((platform, launcher, installer, install_cmd))
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
        'sas printer',
    ):
        assert marker.lower() in doc.lower(), marker

    print('PASS: universal field platform contracts')


if __name__ == '__main__':
    main()
