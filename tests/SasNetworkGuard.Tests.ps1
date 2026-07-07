Import-Module (Join-Path $PSScriptRoot '../scripts/SasNetworkGuard.psm1') -Force

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

$missing = @'
Name                   : Wi-Fi
State                  : disconnected
BSSID                  : NSLIJHS-WAB-BSSID-SHOULD-NOT-MATCH
'@
$parsed = Get-SasCurrentWifiSsidFromNetshText -Text $missing
if ($parsed -ne 'unknown') { throw "Expected unknown, got $parsed" }
if (Test-SasNorthwellWifiSsid -Ssid $parsed) { throw 'Missing SSID should fail closed' }

Write-Host 'SasNetworkGuard PowerShell tests passed'
