#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts' / 'Close-SasChromeGhostSession.ps1'
CMD = ROOT / 'Close-ChromeGhostSession.cmd'
LAUNCHER = ROOT / 'scripts' / 'Invoke-SasUniversalField.ps1'
NETWORK = ROOT / 'scripts' / 'Invoke-SasNetworkAwareField.ps1'
DOC = ROOT / 'docs' / 'UNIVERSAL_FIELD_PLATFORM.md'


def read(path: Path) -> str:
    assert path.is_file(), f'missing {path.relative_to(ROOT)}'
    return path.read_text(encoding='utf-8')


def main() -> None:
    script = read(SCRIPT)
    cmd = read(CMD)
    launcher = read(LAUNCHER)
    network = read(NETWORK)
    doc = read(DOC)

    for marker in (
        "Name = 'chrome.exe'",
        '--type=',
        '--restart',
        'audio\\.mojom\\.AudioService',
        'Chrome_WidgetWin_1',
        'CHROME_GHOST_SESSION',
        'CHROME_GHOST_DETECTED',
        'CHROME_GHOST_CLOSED',
        'CHROME_GHOST_NONE',
        'CHROME_PROCESS_GONE_CRASH_SESSION_RESIDUE',
        'exit_type',
        'Tabs_*',
        'youtube\\.com/watch\\?v=',
        'taskkill.exe',
        '/T',
        '/F',
        'process_tree_terminate_only',
        'mute_or_volume_clamp_allowed = $false',
        'local_process_mutation_performed',
        'HEADLESS_EXCLUDED',
    ):
        assert marker in script, marker

    assert 'Stop-Process -Name' not in script
    assert 'Get-Process chrome | Stop-Process' not in script
    # Close is the fix. Mute/volume APIs must never appear as remediation.
    assert 'SetMute' not in script
    assert 'ISimpleAudioVolume' not in script
    assert 'AudioEndpointVolume' not in script
    assert 'nircmd' not in script.lower()
    assert 'Muting, volume clamps, and mixer band-aids are forbidden' in script

    assert 'scripts\\Close-SasChromeGhostSession.ps1' in cmd
    assert 'where pwsh.exe' in cmd
    assert 'pwsh.exe -NoLogo -NoProfile' in cmd
    assert 'powershell.exe -NoLogo -NoProfile' in cmd
    assert '-Apply' in cmd
    assert 'Usage: Close-ChromeGhostSession.cmd [apply]' in cmd

    assert "'chrome'" in launcher
    assert 'Usage: sas chrome ghost [close|apply]' in launcher
    assert 'Close-SasChromeGhostSession.ps1' in launcher
    chrome_block = launcher.split("    'chrome' {", 1)[1].split("\n    'autologon' {", 1)[0]
    assert 'Assert-SasProtectedForAction' not in chrome_block
    assert '-Apply' in chrome_block

    assert "'chrome' { $intent = 'LocalOnly' }" in network

    for marker in (
        'sas chrome ghost',
        'Close-ChromeGhostSession.cmd',
        'CHROME_GHOST_SESSION',
        '--restart',
        'Remediation is close-only',
        'Muting or clamping volume is forbidden',
    ):
        assert marker.lower() in doc.lower(), marker

    print('PASS: chrome ghost-session discoverability and close contracts')


if __name__ == '__main__':
    main()
