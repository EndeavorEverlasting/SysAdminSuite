#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('BEFORE_SWITCH','AFTER_SWITCH','MANUAL')]
    [string]$Phase,

    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[A-Za-z0-9_.:-]{1,120}$')]
    [string]$RunId,

    [AllowEmptyString()]
    [string]$ExpectedMac = '',

    [AllowEmptyString()]
    [string]$Label = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function ConvertTo-SasNormalizedMac {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $hex = ($Value -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    if ($hex.Length -ne 12) { throw 'ExpectedMac must contain exactly 12 hexadecimal digits.' }
    return (($hex -split '(.{2})' | Where-Object { $_ }) -join '-')
}

function Get-SasRepoCommit {
    param([Parameter(Mandatory=$true)][string]$Root)
    try {
        $git = Get-Command git.exe -ErrorAction Stop
        $value = (& $git.Source -C $Root rev-parse HEAD 2>$null | Select-Object -First 1)
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) { return ([string]$value).Trim() }
    } catch {}
    return $null
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$normalizedExpectedMac = ConvertTo-SasNormalizedMac -Value $ExpectedMac
$stamp = [DateTimeOffset]::Now.ToString('yyyyMMdd-HHmmss')
$outputRoot = Join-Path $repoRoot 'survey\output\hh-cc-reader'
[void](New-Item -ItemType Directory -Force -Path $outputRoot)

$stateRootBase = if ([string]::IsNullOrWhiteSpace($env:ProgramData)) { $env:TEMP } else { $env:ProgramData }
$stateRoot = Join-Path $stateRootBase 'SysAdminSuite\hh-cc-reader'
[void](New-Item -ItemType Directory -Force -Path $stateRoot)
$safeRunId = ($RunId -replace '[^A-Za-z0-9_.-]','_')
$statePath = Join-Path $stateRoot ("home-lab-state-{0}.json" -f $safeRunId)

$configs = @()
try {
    foreach ($config in @(Get-NetIPConfiguration -ErrorAction Stop | Where-Object {
        $_.NetAdapter -and $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address
    })) {
        foreach ($address in @($config.IPv4Address)) {
            $dns = @()
            try {
                $dns = @(Get-DnsClientServerAddress -InterfaceIndex $config.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop |
                    ForEach-Object { $_.ServerAddresses } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            } catch {}

            $configs += [ordered]@{
                interface_alias = [string]$config.InterfaceAlias
                interface_index = [int]$config.InterfaceIndex
                network_profile = [string]$config.NetProfile.Name
                ipv4 = [string]$address.IPAddress
                prefix_length = [int]$address.PrefixLength
                default_gateway = @($config.IPv4DefaultGateway | ForEach-Object { [string]$_.NextHop })
                dns_servers = $dns
            }
        }
    }
} catch {
    throw ("NETWORK_CHECKPOINT_INTERFACE_ENUMERATION_FAILED: {0}" -f $_.Exception.Message)
}
if ($configs.Count -eq 0) {
    throw 'NETWORK_CHECKPOINT_NO_ACTIVE_IPV4: no active IPv4 interface was captured.'
}

$defaultRoutes = @()
try {
    $defaultRoutes = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
        Sort-Object RouteMetric,InterfaceIndex |
        ForEach-Object {
            [ordered]@{
                interface_index = [int]$_.InterfaceIndex
                next_hop = [string]$_.NextHop
                route_metric = [int]$_.RouteMetric
                policy_store = [string]$_.PolicyStore
            }
        })
} catch {
    throw ("NETWORK_CHECKPOINT_ROUTE_ENUMERATION_FAILED: {0}" -f $_.Exception.Message)
}
if ($defaultRoutes.Count -eq 0) {
    throw 'NETWORK_CHECKPOINT_NO_DEFAULT_ROUTE: no IPv4 default route was captured.'
}

$exactMacNeighbors = @()
if ($normalizedExpectedMac) {
    try {
        foreach ($neighbor in @(Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue)) {
            if ([string]::IsNullOrWhiteSpace([string]$neighbor.LinkLayerAddress)) { continue }
            $candidate = $null
            try { $candidate = ConvertTo-SasNormalizedMac -Value ([string]$neighbor.LinkLayerAddress) } catch {}
            if ($candidate -eq $normalizedExpectedMac) {
                $exactMacNeighbors += [ordered]@{
                    interface_index = [int]$neighbor.InterfaceIndex
                    ipv4 = [string]$neighbor.IPAddress
                    mac = $candidate
                    state = [string]$neighbor.State
                }
            }
        }
    } catch {}
}

$networkClassification = $null
$networkLabel = $null
$sessionModule = Join-Path $repoRoot 'scripts\SasOperatorSession.psm1'
if (Test-Path -LiteralPath $sessionModule -PathType Leaf) {
    try {
        Import-Module $sessionModule -Force -ErrorAction Stop
        $network = Get-SasOperatorNetworkClassification -RepoRoot $repoRoot
        $networkClassification = [string]$network.classification
        $networkLabel = [string]$network.label
    } catch {
        throw ("NETWORK_CHECKPOINT_CLASSIFICATION_FAILED: {0}" -f $_.Exception.Message)
    }
}

$wlanText = $null
try {
    $wlanText = (& "$env:SystemRoot\System32\netsh.exe" wlan show interfaces 2>&1 | Out-String).Trim()
} catch {
    $wlanText = "UNAVAILABLE: $($_.Exception.Message)"
}

$receipt = [ordered]@{
    schema_version = 'sas-hh-cc-reader-network-checkpoint/v1'
    timestamp = [DateTimeOffset]::Now.ToString('o')
    run_id = $RunId
    phase = $Phase
    label = $Label
    host = $env:COMPUTERNAME
    repo_commit = Get-SasRepoCommit -Root $repoRoot
    network_classification = $networkClassification
    network_label = $networkLabel
    expected_mac_supplied = [bool]$normalizedExpectedMac
    expected_mac = $normalizedExpectedMac
    active_ipv4 = $configs
    default_routes = $defaultRoutes
    exact_mac_neighbors = $exactMacNeighbors
    wlan_observation = $wlanText
    classification = 'NETWORK_CHECKPOINT_CAPTURED'
    mutation = 'NONE'
}

$receiptPath = Join-Path $outputRoot ("hh-cc-reader-network-checkpoint-{0}-{1}.json" -f $stamp,$Phase.ToLowerInvariant())
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8

$state = [ordered]@{
    schema_version = 'sas-hh-cc-reader-home-lab-state/v1'
    run_id = $RunId
    expected_mac = $normalizedExpectedMac
    prepared_commit = $receipt.repo_commit
    last_phase = $Phase
    last_checkpoint = $receiptPath
    before_checkpoint = $(if ($Phase -eq 'BEFORE_SWITCH') { $receiptPath } else { $null })
    after_checkpoint = $(if ($Phase -eq 'AFTER_SWITCH') { $receiptPath } else { $null })
    network_classification = $networkClassification
    network_label = $networkLabel
    updated_at = [DateTimeOffset]::Now.ToString('o')
}
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try {
        $prior = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if ($prior.run_id -eq $RunId) {
            if ([string]::IsNullOrWhiteSpace($state.expected_mac) -and -not [string]::IsNullOrWhiteSpace([string]$prior.expected_mac)) {
                $state.expected_mac = [string]$prior.expected_mac
            }
            if ($Phase -eq 'AFTER_SWITCH' -and -not [string]::IsNullOrWhiteSpace([string]$prior.prepared_commit)) {
                $state.prepared_commit = [string]$prior.prepared_commit
            }
            if ($Phase -ne 'BEFORE_SWITCH' -and -not [string]::IsNullOrWhiteSpace([string]$prior.before_checkpoint)) {
                $state.before_checkpoint = [string]$prior.before_checkpoint
            }
            if ($Phase -ne 'AFTER_SWITCH' -and -not [string]::IsNullOrWhiteSpace([string]$prior.after_checkpoint)) {
                $state.after_checkpoint = [string]$prior.after_checkpoint
            }
        }
    } catch {}
}
$stateTemp = Join-Path $stateRoot ("{0}.{1}.tmp" -f ([IO.Path]::GetFileName($statePath)),[Guid]::NewGuid().ToString('N'))
$state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $stateTemp -Encoding UTF8
Move-Item -LiteralPath $stateTemp -Destination $statePath -Force

Write-Host ("CLASSIFICATION={0}" -f $receipt.classification)
Write-Host ("EVIDENCE={0}" -f $receiptPath)
Write-Host ("STATE={0}" -f $statePath)
exit 0
