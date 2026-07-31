#Requires -Version 5.1
<#
.SYNOPSIS
Creates an operator-local network-guard allowlist for the currently active domain-authenticated VPN/LAN posture.

.DESCRIPTION
This is a local-only bootstrap for remote work when the workstation remains on ordinary Internet Wi-Fi
while a corporate VPN provides a Windows DomainAuthenticated network profile. It never contacts or
mutates a deployment target and never reads or stores credentials.

The helper refuses broad CIDRs. It records only the exact IPv4 addresses (/32) currently assigned to
active DomainAuthenticated non-Wi-Fi interfaces. When the VPN/interface goes away, those exact local
addresses disappear and the normal network guard fails closed again.

The implementation deliberately uses ordinary PowerShell arrays rather than generic List[T] objects.
Windows PowerShell 5.1 can throw a runtime binder error ("Argument types do not match") when some
enterprise hosts enumerate generic lists through array subexpressions. This field surface must remain
compatible with Windows PowerShell 5.1.

After writing the operator-local policy, the helper also activates that exact file through the process-
scoped SAS_NETWORK_GUARD_CONFIG environment variable. This prevents stale SAS_REPO_ROOT state from
redirecting a later recovery/deployment in the same shell to an older checkout's network policy.
#>
[CmdletBinding()]
param(
    [switch]$ConfirmVpnPosture
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not $ConfirmVpnPosture) {
    throw 'VPN network-guard bootstrap requires -ConfirmVpnPosture.'
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$configRoot = Join-Path $repoRoot 'Config'
$configPath = Join-Path $configRoot 'sas-network-guard.local.json'

Write-Host 'Inspecting active Windows network profiles...' -ForegroundColor Cyan
$profiles = @(Get-NetConnectionProfile -ErrorAction Stop | Where-Object {
    ([string]$_.NetworkCategory) -eq 'DomainAuthenticated' -and (
        ([string]$_.IPv4Connectivity) -in @('Subnet','LocalNetwork','Internet') -or
        ([string]$_.IPv6Connectivity) -in @('Subnet','LocalNetwork','Internet')
    )
})

if ($profiles.Count -eq 0) {
    throw 'No active Windows DomainAuthenticated network profile is present. Connect the Northwell VPN/network first; no local allowlist was written.'
}

$eligibleProfiles = @($profiles | Where-Object {
    ([string]$_.InterfaceAlias) -notmatch '(?i)(wi-?fi|wireless|wlan)'
})
if ($eligibleProfiles.Count -eq 0) {
    throw 'DomainAuthenticated posture was observed only on Wi-Fi. This helper will not convert ordinary Wi-Fi into VPN authority.'
}

$addresses = @()
$profileEvidence = @()
foreach ($profile in $eligibleProfiles) {
    $interfaceIndex = [int]$profile.InterfaceIndex
    Write-Host ("Inspecting DomainAuthenticated interface: {0} [index {1}]" -f ([string]$profile.InterfaceAlias), $interfaceIndex) -ForegroundColor DarkCyan

    $ipv4 = @(Get-NetIPAddress -InterfaceIndex $interfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.IPAddress) -and
        ([string]$_.IPAddress) -notmatch '^127\.' -and
        ([string]$_.IPAddress) -notmatch '^169\.254\.'
    })

    foreach ($address in $ipv4) {
        $cidr = ([string]$address.IPAddress).Trim() + '/32'
        if ($addresses -notcontains $cidr) {
            $addresses += $cidr
        }
    }

    $exactAddresses = @($ipv4 | ForEach-Object { [string]$_.IPAddress })
    $profileEvidence += [pscustomobject][ordered]@{
        interface_alias = [string]$profile.InterfaceAlias
        interface_index = $interfaceIndex
        network_category = [string]$profile.NetworkCategory
        ipv4_connectivity = [string]$profile.IPv4Connectivity
        ipv6_connectivity = [string]$profile.IPv6Connectivity
        exact_ipv4_addresses = $exactAddresses
    }
}

$addresses = @($addresses | Sort-Object -Unique)
if ($addresses.Count -eq 0) {
    throw 'No usable IPv4 address was found on an active DomainAuthenticated non-Wi-Fi interface. No local allowlist was written.'
}

New-Item -ItemType Directory -Path $configRoot -Force | Out-Null
$policy = [pscustomobject][ordered]@{
    allowedDnsSuffixes = @()
    allowedWindowsDomains = @()
    allowedLocalIpCidrs = $addresses
    allowedGatewayCidrs = @()
    allowedDnsServerCidrs = @()
}
$policy | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $configPath -Encoding UTF8

$env:SAS_NETWORK_GUARD_CONFIG = $configPath

$result = [pscustomobject][ordered]@{
    schema_version = 'sas-vpn-network-guard-bootstrap/v1'
    status = 'COMPLETED'
    classification = 'SAS_VPN_NETWORK_GUARD_READY'
    config_path = $configPath
    allowed_local_ip_cidrs = $addresses
    domain_authenticated_profiles = $profileEvidence
    process_environment_config_activated = $true
    target_contact_performed = $false
    target_mutation_performed = $false
    secret_material_collected = $false
}

Write-Host 'SAS_VPN_NETWORK_GUARD_READY' -ForegroundColor Green
Write-Host "Config: $configPath"
Write-Host ('Exact active VPN/LAN IP authority: ' + ($addresses -join ', '))
Write-Host 'Activated SAS_NETWORK_GUARD_CONFIG for this PowerShell process.' -ForegroundColor Green
Write-Host 'No target contact or mutation occurred.' -ForegroundColor Green
$result
