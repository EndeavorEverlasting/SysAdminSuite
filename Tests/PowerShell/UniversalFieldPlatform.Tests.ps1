#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulePath = Join-Path $repoRoot 'scripts\SasFieldPlatform.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "Missing platform module: $modulePath" }
Import-Module $modulePath -Force

function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Equal($Actual,$Expected,[string]$Message) { if ([string]$Actual -ne [string]$Expected) { throw "$Message :: expected=$Expected actual=$Actual" } }

$neutralFixture = $null
$previousRuntimeRoot = $env:SAS_RUNTIME_ROOT
$previousRepoRoot = $env:SAS_REPO_ROOT

try {
    $fixedDrive = { param($drive) 3 }
    $networkDrive = { param($drive) 4 }
    $unknownDrive = { param($drive) 0 }
    Assert-True (Test-SasLocalControllerPath -Path 'C:\SASAL' -DriveTypeResolver $fixedDrive) 'fixed local runtime should be accepted'
    Assert-True (-not (Test-SasLocalControllerPath -Path '\\server\share\SysAdminSuite' -DriveTypeResolver $fixedDrive)) 'UNC controller runtime must be rejected'
    Assert-True (-not (Test-SasLocalControllerPath -Path 'Z:\SysAdminSuite' -DriveTypeResolver $networkDrive)) 'mapped network drive controller runtime must be rejected'
    Assert-True (-not (Test-SasLocalControllerPath -Path 'Z:\SysAdminSuite' -DriveTypeResolver $unknownDrive)) 'unknown drive type must fail closed'

    # Field regression: the installed launcher starts with an empty List[string] of candidates. A
    # mandatory collection parameter used to reject that empty list before C:\SASAL or any later
    # candidate could even be evaluated. Resolve from a neutral working directory with the first
    # environment candidates intentionally empty and prove a later local controller still resolves.
    $neutralFixture = Join-Path $env:TEMP ('sas-neutral-controller-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $neutralFixture 'scripts') -Force | Out-Null
    foreach ($relative in @(
        'scripts\SasNetworkGuard.psm1',
        'scripts\Confirm-SasNorthwellNetwork.ps1',
        'scripts\SasPortableLauncher.ps1',
        'Run-AutoLogonOnsite.cmd'
    )) {
        New-Item -ItemType File -Path (Join-Path $neutralFixture $relative) -Force | Out-Null
    }

    $env:SAS_RUNTIME_ROOT = $null
    $env:SAS_REPO_ROOT = $null
    Push-Location $env:TEMP
    try {
        $resolvedNeutral = Resolve-SasControllerRoot -CallerRoot $neutralFixture
    }
    finally {
        Pop-Location
    }
    Assert-Equal $resolvedNeutral ([IO.Path]::GetFullPath($neutralFixture)) 'neutral-directory controller resolution must accept an initially empty candidate list'

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

    Write-Host 'PASS: universal field platform supports neutral-directory resolution, hardwire, WAB, VPN, and fail-closed machine-local runtime isolation.'
}
finally {
    $env:SAS_RUNTIME_ROOT = $previousRuntimeRoot
    $env:SAS_REPO_ROOT = $previousRepoRoot
    if ($neutralFixture -and (Test-Path -LiteralPath $neutralFixture)) {
        Remove-Item -LiteralPath $neutralFixture -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Module SasFieldPlatform -ErrorAction SilentlyContinue
}
