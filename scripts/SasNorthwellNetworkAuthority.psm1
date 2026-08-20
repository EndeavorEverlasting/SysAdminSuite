Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$guardPath = Join-Path $PSScriptRoot 'SasNetworkGuard.psm1'
if (-not (Test-Path -LiteralPath $guardPath -PathType Leaf)) { throw "Shared Northwell network guard not found: $guardPath" }
Import-Module $guardPath -Force -ErrorAction Stop

function Get-SasNorthwellNetworkAuthority {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Ssid,
        [AllowNull()][string]$NetworkText,
        [AllowNull()][object[]]$ConnectionProfiles,
        [AllowNull()][scriptblock]$AddressResolver
    )

    if (-not $PSBoundParameters.ContainsKey('Ssid')) { $Ssid = Get-SasCurrentWifiSsid }
    if (Test-SasNorthwellWifiSsid -Ssid $Ssid) {
        return [pscustomobject][ordered]@{
            Allowed = $true
            Route = 'WAB_WIFI'
            Evidence = "ssid=$Ssid"
        }
    }

    if (-not $PSBoundParameters.ContainsKey('NetworkText')) { $NetworkText = Get-SasLocalNetworkText }
    $wiredArgs = @{ NetworkText = $NetworkText }
    if ($PSBoundParameters.ContainsKey('ConnectionProfiles')) { $wiredArgs.ConnectionProfiles = $ConnectionProfiles }
    if ($PSBoundParameters.ContainsKey('AddressResolver')) { $wiredArgs.AddressResolver = $AddressResolver }

    if (Test-SasNorthwellWiredEvidence @wiredArgs) {
        $route = 'PROTECTED_NON_WIFI'
        $evidence = 'approved hardwire/authenticated VPN or configured protected route'
        if ($PSBoundParameters.ContainsKey('ConnectionProfiles')) {
            $domainProfiles = @($ConnectionProfiles | Where-Object {
                $null -ne $_ -and
                ([string]$_.NetworkCategory) -eq 'DomainAuthenticated' -and
                ([string]$_.InterfaceAlias) -notmatch '(?i)(wi-?fi|wireless|wlan)'
            })
            if ($domainProfiles.Count -gt 0) {
                $route = 'DOMAIN_AUTHENTICATED_NON_WIFI'
                $evidence = 'interface=' + (($domainProfiles | ForEach-Object { [string]$_.InterfaceAlias }) -join ',')
            }
        }
        return [pscustomobject][ordered]@{
            Allowed = $true
            Route = $route
            Evidence = $evidence
        }
    }

    return [pscustomobject][ordered]@{
        Allowed = $false
        Route = 'UNAUTHORIZED'
        Evidence = "ssid=$Ssid; no approved protected non-Wi-Fi authority"
    }
}

function Assert-SasNorthwellNetwork {
    [CmdletBinding()]
    param()
    $authority = Get-SasNorthwellNetworkAuthority
    if (-not $authority.Allowed) {
        throw "Network check failed: use an approved Northwell path before network-device work. Supported controller paths are WAB Wi-Fi, DomainAuthenticated hardwire/LAN, authenticated VPN, or an explicitly configured protected route. $($authority.Evidence)"
    }
    return $authority
}

Export-ModuleMember -Function Get-SasNorthwellNetworkAuthority, Assert-SasNorthwellNetwork
