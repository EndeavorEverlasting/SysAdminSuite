#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulePath = Join-Path $repoRoot 'scripts\SasFieldPlatform.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "Missing platform module: $modulePath" }
Import-Module $modulePath -Force

function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Equal($Actual,$Expected,[string]$Message) { if ([string]$Actual -ne [string]$Expected) { throw "$Message :: expected=$Expected actual=$Actual" } }

try {
    $fixedDrive = { param($drive) 3 }
    $networkDrive = { param($drive) 4 }
    $unknownDrive = { param($drive) 0 }
    Assert-True (Test-SasLocalControllerPath -Path 'C:\SASAL' -DriveTypeResolver $fixedDrive) 'fixed local runtime should be accepted'
    Assert-True (-not (Test-SasLocalControllerPath -Path '\\server\share\SysAdminSuite' -DriveTypeResolver $fixedDrive)) 'UNC controller runtime must be rejected'
    Assert-True (-not (Test-SasLocalControllerPath -Path 'Z:\SysAdminSuite' -DriveTypeResolver $networkDrive)) 'mapped network drive controller runtime must be rejected'
    Assert-True (-not (Test-SasLocalControllerPath -Path 'Z:\SysAdminSuite' -DriveTypeResolver $unknownDrive)) 'unknown drive type must fail closed'

    $addresses = { param($index) @([pscustomobject]@{ IPAddress='10.44.55.66' }) }

    $wab = @([pscustomobject]@{
        Name='NSLIJHS-WAB-Clinical'; InterfaceAlias='Wi-Fi'; InterfaceIndex=7;
        NetworkCategory='Private'; IPv4Connectivity='Internet'; IPv6Connectivity='NoTraffic'
    })
    $wabResult = Get-SasProtectedNetworkAuthority -ConnectionProfiles $wab -AddressResolver $addresses
    Assert-True ([bool]$wabResult.approved) 'WAB should be approved'
    Assert-Equal $wabResult.authority 'WAB_WIFI' 'WAB authority classification'

    $wired = @([pscustomobject]@{
        Name='nslijhs.net'; InterfaceAlias='Ethernet'; InterfaceIndex=10;
        NetworkCategory='DomainAuthenticated'; IPv4Connectivity='Internet'; IPv6Connectivity='NoTraffic'
    })
    $wiredResult = Get-SasProtectedNetworkAuthority -ConnectionProfiles $wired -AddressResolver $addresses
    Assert-True ([bool]$wiredResult.approved) 'hardwire should be approved'
    Assert-Equal $wiredResult.authority 'DOMAIN_AUTHENTICATED_WIRED' 'hardwire authority classification'

    $vpn = @([pscustomobject]@{
        Name='nslijhs.net'; InterfaceAlias='Citrix Virtual Adapter'; InterfaceIndex=9;
        NetworkCategory='DomainAuthenticated'; IPv4Connectivity='Internet'; IPv6Connectivity='NoTraffic'
    })
    $vpnResult = Get-SasProtectedNetworkAuthority -ConnectionProfiles $vpn -AddressResolver $addresses
    Assert-True ([bool]$vpnResult.approved) 'VPN should be approved'
    Assert-Equal $vpnResult.authority 'DOMAIN_AUTHENTICATED_VPN' 'VPN authority classification'

    $guest = @([pscustomobject]@{
        Name='MyOptimum'; InterfaceAlias='Wi-Fi'; InterfaceIndex=5;
        NetworkCategory='Public'; IPv4Connectivity='Internet'; IPv6Connectivity='NoTraffic'
    })
    $guestResult = Get-SasProtectedNetworkAuthority -ConnectionProfiles $guest -AddressResolver $addresses
    Assert-True (-not [bool]$guestResult.approved) 'guest-only path should remain blocked'
    Assert-Equal $guestResult.authority 'UNPROVEN' 'guest-only authority classification'

    Write-Host 'PASS: universal field platform supports hardwire, WAB, VPN, and fail-closed machine-local runtime isolation.'
}
finally {
    Remove-Module SasFieldPlatform -ErrorAction SilentlyContinue
}
