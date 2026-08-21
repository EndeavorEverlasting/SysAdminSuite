#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts' / 'Reset-SasClipboard.ps1'
CMD = ROOT / 'Reset-SysAdminSuiteClipboard.cmd'
LAUNCHER = ROOT / 'scripts' / 'Invoke-SasUniversalField.ps1'
DOC = ROOT / 'docs' / 'UNIVERSAL_FIELD_PLATFORM.md'


def read(path: Path) -> str:
    assert path.is_file(), f'missing {path.relative_to(ROOT)}'
    return path.read_text(encoding='utf-8')


def main() -> None:
    script = read(SCRIPT)
    cmd = read(CMD)
    launcher = read(LAUNCHER)
    doc = read(DOC)

    # Preserve the exact field-proven repair primitive and keep it narrowly scoped.
    assert 'Get-Service cbdhsvc* | Restart-Service -Force' in script
    assert "Get-Service -Name 'cbdhsvc*'" in script
    assert 'Restart-Service -Force -ErrorAction Stop' in script
    assert 'CLIPBOARD_RESET_OK' in script
    assert "Status -ne 'Running'" in script
    for forbidden in ('Stop-Process', 'Restart-Computer', 'Stop-Service spooler', 'Clear-Clipboard'):
        assert forbidden.lower() not in script.lower(), forbidden

    # One visible root launcher should prefer pwsh (matching the proven field shell) and fall back to 5.1.
    assert 'scripts\\Reset-SasClipboard.ps1' in cmd
    assert 'where pwsh.exe' in cmd
    assert 'pwsh.exe -NoLogo -NoProfile' in cmd
    assert 'powershell.exe -NoLogo -NoProfile' in cmd

    # The installed universal front door exposes the repair without a protected-network gate.
    assert "'clipboard'" in launcher
    assert 'Usage: sas clipboard [reset]' in launcher
    assert 'Reset-SasClipboard.ps1' in launcher
    clipboard_block = launcher.split("    'clipboard' {", 1)[1].split("\n    'autologon' {", 1)[0]
    assert 'Assert-SasProtectedForAction' not in clipboard_block

    for marker in (
        'sas clipboard',
        'Reset-SysAdminSuiteClipboard.cmd',
        'Get-Service cbdhsvc* | Restart-Service -Force',
    ):
        assert marker.lower() in doc.lower(), marker

    print('PASS: clipboard reset discoverability and field-proven mechanism contracts')


if __name__ == '__main__':
    main()
