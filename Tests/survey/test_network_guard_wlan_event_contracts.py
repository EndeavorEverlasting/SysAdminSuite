#!/usr/bin/env python3
"""Static contracts for Windows WLAN event-log fallback and repo-relative guard config."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "scripts" / "SasNetworkGuard.psm1"


def main() -> None:
    text = MODULE.read_text(encoding="utf-8")
    required = (
        "Get-SasWlanConnectionFromEventXml",
        "Get-SasCurrentWifiSsidFromWlanEventLog",
        "Microsoft-Windows-WLAN-AutoConfig/Operational",
        "Id = 8001",
        "ProfileName",
        "SSID",
        "Get-NetAdapter -InterfaceIndex",
        "Get-SasCurrentWifiSsidFromWlanEventLog",
        "Join-Path $PSScriptRoot '..'",
        "Config\\sas-network-guard.local.json",
    )
    missing = [marker for marker in required if marker not in text]
    assert not missing, f"missing WLAN event/config-path markers: {missing}"
    netsh_index = text.index("netsh wlan show interfaces")
    event_index = text.index("Get-SasCurrentWifiSsidFromWlanEventLog", netsh_index)
    profile_index = text.index("Get-NetConnectionProfile -ErrorAction Stop", event_index)
    assert netsh_index < event_index < profile_index
    assert "return 'Config/sas-network-guard.local.json'" not in text
    print("PASS: WLAN event fallback and repo-relative guard config contracts")


if __name__ == "__main__":
    main()
