Import-Module (Join-Path $PSScriptRoot '../scripts/SasNetworkGuard.psm1') -Force

$temp = New-Item -ItemType Directory -Path ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.Guid]::NewGuid().ToString()))
try {
    $env:SAS_NETWORK_GUARD_CONFIG = Join-Path $temp.FullName 'guard.json'

    $cases = @(
        @{ Ssid = 'NSLIJHS-WAB'; Expected = $true },
        @{ Ssid = 'NSLIJHS-WAB2'; Expected = $true },
        @{ Ssid = 'NSLIJHS-WAB-TEST'; Expected = $true },
        @{ Ssid = 'Guest-WiFi'; Expected = $false },
        @{ Ssid = ''; Expected = $false },
        @{ Ssid = 'unknown'; Expected = $false }
    )
    foreach ($case in $cases) {
        $actual = Test-SasNorthwellWifiSsid -Ssid $case.Ssid
        if ($actual -ne $case.Expected) { throw "SSID '$($case.Ssid)' expected $($case.Expected) got $actual" }
    }

    $sample = @'
Name                   : Wi-Fi
State                  : connected
BSSID                  : NSLIJHS-WAB-BSSID-SHOULD-NOT-MATCH
SSID                   : Guest-WiFi
'@
    $parsed = Get-SasCurrentWifiSsidFromNetshText -Text $sample
    if ($parsed -ne 'Guest-WiFi') { throw "Expected Guest-WiFi, got $parsed" }
    if (Test-SasNorthwellWifiSsid -Ssid $parsed) { throw 'BSSID was mistaken for SSID' }

    $networkText = @'
Windows IP Configuration
   Primary Dns Suffix  . . . . . . . : corp.example.invalid
Ethernet adapter Ethernet:
   Connection-specific DNS Suffix  . : wired.example.invalid
   IPv4 Address. . . . . . . . . . . : 192.0.2.25(Preferred)
   Default Gateway . . . . . . . . . : 192.0.2.1
   DNS Servers . . . . . . . . . . . : 198.51.100.10
'@
    @{
        allowedDnsSuffixes = @('wired.example.invalid')
        allowedLocalIpCidrs = @('192.0.2.0/24')
        allowedGatewayCidrs = @('192.0.2.1/32')
        allowedDnsServerCidrs = @('198.51.100.0/24')
    } | ConvertTo-Json | Set-Content -LiteralPath $env:SAS_NETWORK_GUARD_CONFIG

    if (-not (Test-SasNorthwellWiredEvidence -NetworkText $networkText)) { throw 'approved wired evidence should pass' }
    if (-not (Test-SasNorthwellNetworkPosture -Ssid 'Guest-WiFi' -NetworkText $networkText)) { throw 'approved wired evidence should pass with guest Wi-Fi' }

    '{}' | Set-Content -LiteralPath $env:SAS_NETWORK_GUARD_CONFIG
    if (Test-SasNorthwellWiredEvidence -NetworkText $networkText) { throw 'missing wired allowlist should fail' }

    '{ not json' | Set-Content -LiteralPath $env:SAS_NETWORK_GUARD_CONFIG
    if (Test-SasNorthwellWiredEvidence -NetworkText $networkText) { throw 'malformed config should fail closed' }

    Write-Host 'SasNetworkGuard PowerShell tests passed'
} finally {
    Remove-Item Env:SAS_NETWORK_GUARD_CONFIG -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
