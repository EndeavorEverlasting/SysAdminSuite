#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[A-Za-z0-9_.:-]{1,120}$')]
    [string]$RunId,

    [AllowEmptyString()]
    [string]$ExpectedMac = '',

    [ValidateRange(1,2048)]
    [int]$MaxHosts = 512,

    [ValidateRange(20,1000)]
    [int]$PingTimeoutMs = 90
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

function Test-SasPrivateIPv4 {
    param([Parameter(Mandatory=$true)][System.Net.IPAddress]$Address)
    $b = $Address.GetAddressBytes()
    if ($b.Length -ne 4) { return $false }
    if ($b[0] -eq 10) { return $true }
    if ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) { return $true }
    if ($b[0] -eq 192 -and $b[1] -eq 168) { return $true }
    return $false
}

function ConvertTo-SasIPv4Integer {
    param([Parameter(Mandatory=$true)][System.Net.IPAddress]$Address)
    $b = $Address.GetAddressBytes()
    return [uint64]$b[0] * 16777216 + [uint64]$b[1] * 65536 + [uint64]$b[2] * 256 + [uint64]$b[3]
}

function ConvertFrom-SasIPv4Integer {
    param([Parameter(Mandatory=$true)][uint64]$Value)
    $a = [int](($Value -shr 24) -band 255)
    $b = [int](($Value -shr 16) -band 255)
    $c = [int](($Value -shr 8) -band 255)
    $d = [int]($Value -band 255)
    return [System.Net.IPAddress]::Parse(("{0}.{1}.{2}.{3}" -f $a,$b,$c,$d))
}

function Get-SasNeighbors {
    param([Parameter(Mandatory=$true)][int]$InterfaceIndex)
    $items = @()
    foreach ($neighbor in @(Get-NetNeighbor -AddressFamily IPv4 -InterfaceIndex $InterfaceIndex -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace([string]$neighbor.LinkLayerAddress)) { continue }
        $mac = $null
        try { $mac = ConvertTo-SasNormalizedMac -Value ([string]$neighbor.LinkLayerAddress) } catch { continue }
        if (-not $mac) { continue }
        $items += [ordered]@{
            ipv4 = [string]$neighbor.IPAddress
            mac = $mac
            state = [string]$neighbor.State
            interface_index = [int]$neighbor.InterfaceIndex
        }
    }
    return @($items)
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$outputRoot = Join-Path $repoRoot 'survey\output\hh-cc-reader'
[void](New-Item -ItemType Directory -Force -Path $outputRoot)

$stateRootBase = if ([string]::IsNullOrWhiteSpace($env:ProgramData)) { $env:TEMP } else { $env:ProgramData }
$statePath = Join-Path $stateRootBase 'SysAdminSuite\hh-cc-reader\home-lab-state.json'
$normalizedExpectedMac = ConvertTo-SasNormalizedMac -Value $ExpectedMac

if (-not $normalizedExpectedMac -and (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if ([string]$state.run_id -eq $RunId -and -not [string]::IsNullOrWhiteSpace([string]$state.expected_mac)) {
            $normalizedExpectedMac = ConvertTo-SasNormalizedMac -Value ([string]$state.expected_mac)
        }
    } catch {}
}
if (-not $normalizedExpectedMac) {
    throw 'Expected MAC is required for identity-safe home-lab discovery. Supply it or run Prepare-HHCCReaderNetworkSwitch.cmd first with an expected MAC.'
}

$checkpoint = Join-Path $PSScriptRoot 'Invoke-SasHhCcReaderNetworkCheckpoint.ps1'
if (Test-Path -LiteralPath $checkpoint -PathType Leaf) {
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $checkpoint -Phase AFTER_SWITCH -RunId $RunId -ExpectedMac $normalizedExpectedMac -Label 'home-lab-discovery'
    if ($LASTEXITCODE -ne 0) { throw 'AFTER_SWITCH checkpoint failed; discovery did not start.' }
}

$routes = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
    Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' } |
    Sort-Object RouteMetric,InterfaceIndex)
if ($routes.Count -eq 0) { throw 'No active IPv4 default route was found.' }

$selectedRoute = $null
$selectedAddress = $null
foreach ($route in $routes) {
    $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -and
            -not $_.IPAddress.StartsWith('169.254.') -and
            $_.IPAddress -ne '127.0.0.1'
        })
    foreach ($address in $addresses) {
        $ip = $null
        if ([System.Net.IPAddress]::TryParse([string]$address.IPAddress,[ref]$ip) -and (Test-SasPrivateIPv4 -Address $ip)) {
            $selectedRoute = $route
            $selectedAddress = $address
            break
        }
    }
    if ($selectedAddress) { break }
}
if (-not $selectedAddress) { throw 'No private IPv4 address was found on an interface owning the default route.' }

$localIp = [System.Net.IPAddress]::Parse([string]$selectedAddress.IPAddress)
$prefixLength = [int]$selectedAddress.PrefixLength
if ($prefixLength -lt 1 -or $prefixLength -gt 30) {
    throw ("Unsupported IPv4 prefix length for bounded consumer-lab discovery: /{0}" -f $prefixLength)
}

$localInteger = ConvertTo-SasIPv4Integer -Address $localIp
$blockSize = [uint64][math]::Pow(2,(32 - $prefixLength))
$networkInteger = [uint64]([math]::Floor($localInteger / $blockSize) * $blockSize)
$broadcastInteger = $networkInteger + $blockSize - 1
$hostCount = [int]($blockSize - 2)
if ($hostCount -gt $MaxHosts) {
    throw ("HOME_LAB_SCOPE_TOO_LARGE: current /{0} contains {1} host addresses; limit is {2}. No active discovery was run." -f $prefixLength,$hostCount,$MaxHosts)
}

$before = Get-SasNeighbors -InterfaceIndex ([int]$selectedRoute.InterfaceIndex)
$exactBefore = @($before | Where-Object { $_.mac -eq $normalizedExpectedMac })
$activeDiscoveryRan = $false

if ($exactBefore.Count -eq 0) {
    $activeDiscoveryRan = $true
    $pinger = New-Object System.Net.NetworkInformation.Ping
    try {
        for ($value = $networkInteger + 1; $value -lt $broadcastInteger; $value++) {
            $candidate = ConvertFrom-SasIPv4Integer -Value $value
            if ($candidate.ToString() -eq $localIp.ToString()) { continue }
            try { [void]$pinger.Send($candidate,$PingTimeoutMs) } catch {}
        }
    }
    finally {
        $pinger.Dispose()
    }
}

Start-Sleep -Milliseconds 250
$after = Get-SasNeighbors -InterfaceIndex ([int]$selectedRoute.InterfaceIndex)
$exactAfter = @($after | Where-Object { $_.mac -eq $normalizedExpectedMac })
$expectedOui = (($normalizedExpectedMac -replace '-','').Substring(0,6))
$sameOui = @($after | Where-Object {
    (($_.mac -replace '-','').Substring(0,6)) -eq $expectedOui -and $_.mac -ne $normalizedExpectedMac
})

$targetIp = $null
$classification = $null
if ($exactAfter.Count -eq 1) {
    $targetIp = [string]$exactAfter[0].ipv4
    $classification = 'HOME_LAB_EXACT_MAC_MATCH'
} elseif ($exactAfter.Count -gt 1) {
    $classification = 'HOME_LAB_EXACT_MAC_AMBIGUOUS'
} else {
    $classification = 'HOME_LAB_EXACT_MAC_NOT_FOUND'
}

$probeExit = $null
$probeClassification = $null
if ($targetIp) {
    $probe = Join-Path $PSScriptRoot 'Invoke-SasHhCcReaderProbe.ps1'
    if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { throw 'Canonical reader probe implementation is missing.' }

    Write-Host ("READER_IPV4={0}" -f $targetIp)
    Write-Host 'Exact MAC match recovered; invoking the existing canonical reader probe from the sealed runtime.'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $probe -IPAddress $targetIp -ExpectedMac $normalizedExpectedMac
    $probeExit = [int]$LASTEXITCODE
    $probeClassification = if ($probeExit -eq 0) { 'READ_ONLY_PROBE_COMPLETE' } else { 'PROBE_BLOCKED_OR_FAILED' }
    $classification = if ($probeExit -eq 0) {
        'HOME_LAB_EXACT_MAC_MATCH_PROBE_COMPLETE'
    } else {
        'HOME_LAB_EXACT_MAC_MATCH_PROBE_BLOCKED'
    }
}

$stamp = [DateTimeOffset]::Now.ToString('yyyyMMdd-HHmmss')
$result = [ordered]@{
    schema_version = 'sas-hh-cc-reader-home-lab-discovery/v1'
    timestamp = [DateTimeOffset]::Now.ToString('o')
    run_id = $RunId
    network_environment = 'AUTHORIZED_CONSUMER_LAB'
    source_interface = [ordered]@{
        interface_index = [int]$selectedRoute.InterfaceIndex
        local_ipv4 = $localIp.ToString()
        prefix_length = $prefixLength
        default_gateway = [string]$selectedRoute.NextHop
        bounded_host_count = $hostCount
    }
    expected_mac = $normalizedExpectedMac
    expected_oui = $expectedOui
    active_host_presence_discovery_ran = $activeDiscoveryRan
    ping_timeout_ms = $PingTimeoutMs
    neighbors_before = $before
    neighbors_after = $after
    exact_mac_matches = $exactAfter
    same_oui_candidates = $sameOui
    reader_ipv4 = $targetIp
    reader_ip_source = if ($targetIp) { 'BOUNDED_LOCAL_DISCOVERY_EXACT_MAC' } else { $null }
    probe_invoked = [bool]$targetIp
    probe_exit_code = $probeExit
    probe_classification = $probeClassification
    classification = $classification
    interpretation_ceiling = 'Exact-MAC match can identify one same-L2 candidate for the canonical probe. Same-OUI candidates are advisory only. No result proves firmware-management ownership.'
    mutation = 'NONE'
}

$receiptPath = Join-Path $outputRoot ("hh-cc-reader-home-lab-discovery-{0}.json" -f $stamp)
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $receiptPath -Encoding UTF8

Write-Host ("CLASSIFICATION={0}" -f $classification)
Write-Host ("EVIDENCE={0}" -f $receiptPath)
if (-not $targetIp -and $sameOui.Count -gt 0) {
    Write-Host ("SAME_OUI_CANDIDATES={0}" -f $sameOui.Count)
    Write-Host 'NOTE: same-OUI candidates are not promoted to reader identity without stronger corroboration.'
}
if ($classification -eq 'HOME_LAB_EXACT_MAC_AMBIGUOUS') { exit 5 }
if ($targetIp -and $probeExit -ne 0) { exit $probeExit }
exit 0
