#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$IPAddress,

    [Parameter(Position=1)]
    [AllowEmptyString()]
    [string]$ExpectedMac = '',

    [ValidateRange(1,20)]
    [int]$PingCount = 4,

    [ValidateRange(1,65535)]
    [int]$TcpPort = 443
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function ConvertTo-SasNormalizedMac {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $hex = ($Value -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    if ($hex.Length -ne 12) {
        throw 'ExpectedMac must contain exactly 12 hexadecimal digits.'
    }
    return (($hex -split '(.{2})' | Where-Object { $_ }) -join '-')
}

function Test-SasSameIPv4Subnet {
    param(
        [Parameter(Mandatory=$true)][System.Net.IPAddress]$Left,
        [Parameter(Mandatory=$true)][System.Net.IPAddress]$Right,
        [Parameter(Mandatory=$true)][int]$PrefixLength
    )

    if ($Left.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork -or
        $Right.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork -or
        $PrefixLength -lt 0 -or $PrefixLength -gt 32) {
        return $false
    }

    $leftBytes = $Left.GetAddressBytes()
    $rightBytes = $Right.GetAddressBytes()
    $fullBytes = [int][Math]::Floor($PrefixLength / 8)
    $remainder = $PrefixLength % 8

    for ($i = 0; $i -lt $fullBytes; $i++) {
        if ($leftBytes[$i] -ne $rightBytes[$i]) { return $false }
    }
    if ($remainder -gt 0) {
        $mask = [byte](0xFF -band (0xFF -shl (8 - $remainder)))
        if (($leftBytes[$fullBytes] -band $mask) -ne ($rightBytes[$fullBytes] -band $mask)) {
            return $false
        }
    }
    return $true
}

function Write-SasProbeResult {
    param(
        [Parameter(Mandatory=$true)][System.Collections.IDictionary]$Result,
        [Parameter(Mandatory=$true)][string]$RepoRoot
    )

    $outputRoot = Join-Path $RepoRoot 'survey\output\hh-cc-reader'
    [void](New-Item -ItemType Directory -Force -Path $outputRoot)
    $stamp = [DateTimeOffset]::Now.ToString('yyyyMMdd-HHmmss')
    $path = Join-Path $outputRoot ("hh-cc-reader-probe-{0}.json" -f $stamp)
    $Result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    Write-Host ("EVIDENCE={0}" -f $path)
}

$target = $null
if (-not [System.Net.IPAddress]::TryParse($IPAddress, [ref]$target) -or
    $target.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'IPAddress must be one explicit IPv4 address. CIDRs, ranges, wildcards, and hostnames are refused.'
}

$normalizedExpectedMac = ConvertTo-SasNormalizedMac -Value $ExpectedMac
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

$result = [ordered]@{
    schema_version = 'sas-hh-cc-reader-probe/v1'
    timestamp = [DateTimeOffset]::Now.ToString('o')
    organization = 'health-and-hospitals'
    mode = 'read-only'
    target_ip = $target.ToString()
    expected_mac_supplied = -not [string]::IsNullOrWhiteSpace($normalizedExpectedMac)
    network = @()
    selected_interface = $null
    neighbor = $null
    ping = $null
    detailed = $null
    tcp = $null
    classification = 'STARTED'
}

Write-Host '=== H&H CC READER READ-ONLY PROBE ==='
Write-Host ("TARGET={0}" -f $target)

$configs = @(Get-NetIPConfiguration | Where-Object {
    $_.NetAdapter -and $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address
})

$rows = New-Object 'System.Collections.Generic.List[object]'
foreach ($config in $configs) {
    foreach ($address in @($config.IPv4Address)) {
        $localIp = $null
        if (-not [System.Net.IPAddress]::TryParse([string]$address.IPAddress, [ref]$localIp)) { continue }
        if ($localIp.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { continue }
        if ($localIp.IsIPv6LinkLocal -or $localIp.ToString().StartsWith('169.254.')) { continue }

        $same = Test-SasSameIPv4Subnet -Left $localIp -Right $target -PrefixLength ([int]$address.PrefixLength)
        $row = [pscustomobject]@{
            Network = [string]$config.NetProfile.Name
            Interface = [string]$config.InterfaceAlias
            LocalAddress = $localIp.ToString()
            PrefixLength = [int]$address.PrefixLength
            SameSubnet = [bool]$same
        }
        [void]$rows.Add($row)
        Write-Host ("NET={0} IF={1} PC={2}/{3} SAME={4}" -f $row.Network,$row.Interface,$row.LocalAddress,$row.PrefixLength,$row.SameSubnet)
    }
}

$result.network = @($rows)
$candidates = @($rows | Where-Object { $_.SameSubnet })
if ($candidates.Count -eq 0) {
    $result.classification = 'NETWORK_MISMATCH'
    Write-Host 'CLASSIFICATION=NETWORK_MISMATCH'
    Write-Host 'STOP: no active IPv4 interface is on the target subnet. Do not interpret reader probe failures.'
    Write-SasProbeResult -Result $result -RepoRoot $repoRoot
    exit 3
}
if ($candidates.Count -gt 1) {
    $result.classification = 'NETWORK_AMBIGUOUS'
    Write-Host 'CLASSIFICATION=NETWORK_AMBIGUOUS'
    Write-Host 'STOP: more than one active interface matches the target subnet. Resolve interface/network placement first.'
    Write-SasProbeResult -Result $result -RepoRoot $repoRoot
    exit 4
}

$selected = $candidates[0]
$result.selected_interface = $selected
Write-Host ("SELECTED_IF={0} SOURCE={1}/{2}" -f $selected.Interface,$selected.LocalAddress,$selected.PrefixLength)

# One harmless echo attempt primes local neighbor resolution when L2 adjacency exists.
$neighborPrime = Test-Connection -ComputerName $target.ToString() -Count 1 -Quiet -ErrorAction SilentlyContinue
$neighbor = Get-NetNeighbor -IPAddress $target.ToString() -ErrorAction SilentlyContinue |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.LinkLayerAddress) } |
    Select-Object -First 1

$observedMac = if ($neighbor) { ConvertTo-SasNormalizedMac -Value ([string]$neighbor.LinkLayerAddress) } else { $null }
$deviceMatch = $null
if ($normalizedExpectedMac) {
    $deviceMatch = $observedMac -and $observedMac -eq $normalizedExpectedMac
}
$result.neighbor = [ordered]@{
    observed_mac = $observedMac
    state = if ($neighbor) { [string]$neighbor.State } else { $null }
    expected_mac = $normalizedExpectedMac
    device_match = $deviceMatch
}
Write-Host ("MAC={0}" -f $(if ($observedMac) { $observedMac } else { 'UNRESOLVED' }))
if ($normalizedExpectedMac) {
    Write-Host ("DEVICE_MATCH={0}" -f [bool]$deviceMatch)
    if (-not $deviceMatch) {
        $result.classification = if ($observedMac) { 'DEVICE_MISMATCH' } else { 'DEVICE_UNRESOLVED' }
        Write-Host ("CLASSIFICATION={0}" -f $result.classification)
        Write-Host 'STOP: expected device identity was not proven. No higher-layer target interpretation follows.'
        Write-SasProbeResult -Result $result -RepoRoot $repoRoot
        exit 5
    }
} else {
    Write-Host 'DEVICE_MATCH=UNVERIFIED (no expected MAC supplied)'
}

$pingReplies = @(Test-Connection -ComputerName $target.ToString() -Count $PingCount -ErrorAction SilentlyContinue)
$result.ping = [ordered]@{
    requested = $PingCount
    received = $pingReplies.Count
    succeeded = ($pingReplies.Count -gt 0)
}
Write-Host ("PING_RECEIVED={0}/{1}" -f $pingReplies.Count,$PingCount)

$detailed = Test-NetConnection -ComputerName $target.ToString() -InformationLevel Detailed -WarningAction SilentlyContinue
$result.detailed = [ordered]@{
    remote_address = [string]$detailed.RemoteAddress
    interface_alias = [string]$detailed.InterfaceAlias
    source_address = [string]$detailed.SourceAddress
    ping_succeeded = [bool]$detailed.PingSucceeded
}
Write-Host ("DETAIL SOURCE={0} IF={1} PING={2}" -f $result.detailed.source_address,$result.detailed.interface_alias,$result.detailed.ping_succeeded)

$tcp = Test-NetConnection -ComputerName $target.ToString() -Port $TcpPort -InformationLevel Detailed -WarningAction SilentlyContinue
$result.tcp = [ordered]@{
    remote_address = [string]$tcp.RemoteAddress
    remote_port = $TcpPort
    interface_alias = [string]$tcp.InterfaceAlias
    source_address = [string]$tcp.SourceAddress
    tcp_test_succeeded = [bool]$tcp.TcpTestSucceeded
}
Write-Host ("TCP_{0}={1}" -f $TcpPort,$result.tcp.tcp_test_succeeded)

$result.classification = 'READ_ONLY_PROBE_COMPLETE'
Write-Host 'CLASSIFICATION=READ_ONLY_PROBE_COMPLETE'
Write-Host 'NOTE: reachability does not identify service ownership or prove a firmware-management path.'
Write-SasProbeResult -Result $result -RepoRoot $repoRoot
exit 0
