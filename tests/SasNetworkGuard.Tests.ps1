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

    $wlanSuccessXml = @'
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <System><EventID>8001</EventID></System>
  <EventData>
    <Data Name="InterfaceGuid">{11111111-2222-3333-4444-555555555555}</Data>
    <Data Name="ProfileName">NSLIJHS-WAB(WPA2)</Data>
    <Data Name="SSID">NSLIJHS-WAB</Data>
  </EventData>
</Event>
'@
    $wlanSuccess = Get-SasWlanConnectionFromEventXml -XmlText $wlanSuccessXml
    if ($null -eq $wlanSuccess) { throw 'Expected WLAN success event to parse.' }
    if ($wlanSuccess.ssid -ne 'NSLIJHS-WAB') { throw "Expected WLAN event SSID NSLIJHS-WAB, got $($wlanSuccess.ssid)" }
    if ($wlanSuccess.profile_name -ne 'NSLIJHS-WAB(WPA2)') { throw "Expected WLAN profile name, got $($wlanSuccess.profile_name)" }

    $connectionProfiles = @(
        [pscustomobject]@{ Name = 'Ethernet Network'; InterfaceAlias = 'Ethernet' },
        [pscustomobject]@{ Name = 'NSLIJHS-WAB'; InterfaceAlias = 'Wi-Fi' }
    )
    $profileSsid = Get-SasWifiSsidFromConnectionProfiles -Profiles $connectionProfiles
    if ($profileSsid -ne 'NSLIJHS-WAB') { throw "Expected connection-profile fallback NSLIJHS-WAB, got $profileSsid" }

    $guestProfiles = @([pscustomobject]@{ Name = 'Guest-WiFi'; InterfaceAlias = 'Wi-Fi' })
    $guestProfileSsid = Get-SasWifiSsidFromConnectionProfiles -Profiles $guestProfiles
    if ($guestProfileSsid -ne 'Guest-WiFi') { throw "Expected Guest-WiFi fallback, got $guestProfileSsid" }

    $wiredOnlyProfiles = @([pscustomobject]@{ Name = 'Corporate LAN'; InterfaceAlias = 'Ethernet' })
    $wiredOnlySsid = Get-SasWifiSsidFromConnectionProfiles -Profiles $wiredOnlyProfiles
    if ($wiredOnlySsid -ne 'unknown') { throw "Wired profile must not be reported as Wi-Fi SSID; got $wiredOnlySsid" }

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

    @{
        allowedDnsSuffixes = @()
        allowedWindowsDomains = @()
        allowedLocalIpCidrs = @('100.100.27.140/32')
        allowedGatewayCidrs = @()
        allowedDnsServerCidrs = @()
    } | ConvertTo-Json | Set-Content -LiteralPath $env:SAS_NETWORK_GUARD_CONFIG

    $vpnProfiles = @(
        [pscustomobject]@{
            Name = 'nslijhs.net'
            InterfaceAlias = 'Citrix Virtual Adapter'
            InterfaceIndex = 9
            NetworkCategory = 'DomainAuthenticated'
            IPv4Connectivity = 'Internet'
            IPv6Connectivity = 'NoTraffic'
        }
    )
    $vpnResolver = {
        param($InterfaceIndex)
        if ($InterfaceIndex -eq 9) {
            return @([pscustomobject]@{ IPAddress = '100.100.27.140' })
        }
        return @()
    }

    if (-not (Test-SasNorthwellDomainAuthenticatedEvidence -ConnectionProfiles $vpnProfiles -AddressResolver $vpnResolver)) {
        throw 'exact /32 on active DomainAuthenticated non-Wi-Fi VPN interface should pass'
    }
    if (-not (Test-SasNorthwellNetworkPosture -Ssid 'Guest-WiFi' -NetworkText '' -ConnectionProfiles $vpnProfiles -AddressResolver $vpnResolver)) {
        throw 'guest Wi-Fi plus exact approved DomainAuthenticated VPN interface should pass'
    }

    $wifiOnlyDomain = @(
        [pscustomobject]@{
            Name = 'Guest-WiFi'
            InterfaceAlias = 'Wi-Fi'
            InterfaceIndex = 4
            NetworkCategory = 'DomainAuthenticated'
            IPv4Connectivity = 'Internet'
            IPv6Connectivity = 'NoTraffic'
        }
    )
    $wifiResolver = { param($InterfaceIndex) @([pscustomobject]@{ IPAddress = '100.100.27.140' }) }
    if (Test-SasNorthwellNetworkPosture -Ssid 'Guest-WiFi' -NetworkText '' -ConnectionProfiles $wifiOnlyDomain -AddressResolver $wifiResolver) {
        throw 'DomainAuthenticated Wi-Fi must not be converted into VPN/LAN authority'
    }

    $wrongVpnResolver = { param($InterfaceIndex) @([pscustomobject]@{ IPAddress = '100.100.27.141' }) }
    if (Test-SasNorthwellNetworkPosture -Ssid 'Guest-WiFi' -NetworkText '' -ConnectionProfiles $vpnProfiles -AddressResolver $wrongVpnResolver) {
        throw 'DomainAuthenticated VPN with a non-allowlisted IP must fail closed'
    }

    $privateOnly = @(
        [pscustomobject]@{
            Name = 'Public Internet'
            InterfaceAlias = 'Citrix Virtual Adapter'
            InterfaceIndex = 9
            NetworkCategory = 'Private'
            IPv4Connectivity = 'Internet'
            IPv6Connectivity = 'NoTraffic'
        }
    )
    if (Test-SasNorthwellNetworkPosture -Ssid 'Guest-WiFi' -NetworkText '' -ConnectionProfiles $privateOnly -AddressResolver $vpnResolver) {
        throw 'non-DomainAuthenticated virtual adapter must not authorize target operations'
    }

    '{}' | Set-Content -LiteralPath $env:SAS_NETWORK_GUARD_CONFIG
    if (Test-SasNorthwellWiredEvidence -NetworkText $networkText -ConnectionProfiles @() -AddressResolver { param($i) @() }) { throw 'missing wired allowlist should fail' }

    '{ not json' | Set-Content -LiteralPath $env:SAS_NETWORK_GUARD_CONFIG
    if (Test-SasNorthwellWiredEvidence -NetworkText $networkText -ConnectionProfiles @() -AddressResolver { param($i) @() }) { throw 'malformed config should fail closed' }

    Write-Host 'SasNetworkGuard PowerShell tests passed'
} finally {
    Remove-Item Env:SAS_NETWORK_GUARD_CONFIG -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
