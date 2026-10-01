#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[A-Za-z0-9_.:-]{1,120}$')]
    [string]$RunId,

    [Parameter(Mandatory=$true)]
    [switch]$ConfirmConsumerLab,

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

function Get-SasRepoCommit {
    param([Parameter(Mandatory=$true)][string]$Root)
    $git = Get-Command git.exe -ErrorAction Stop
    $value = (& $git.Source -C $Root rev-parse HEAD 2>$null | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace([string]$value)) { throw 'Could not resolve sealed runtime HEAD.' }
    return ([string]$value).Trim()
}

function Get-SasNeighbors {
    param([Parameter(Mandatory=$true)][int]$InterfaceIndex)
    $items = @()
    foreach ($neighbor in @(Get-NetNeighbor -AddressFamily IPv4 -InterfaceIndex $InterfaceIndex -ErrorAction Stop)) {
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

function Test-SasNeighborInCurrentSubnet {
    param(
        [Parameter(Mandatory=$true)][object]$Neighbor,
        [Parameter(Mandatory=$true)][uint64]$NetworkInteger,
        [Parameter(Mandatory=$true)][uint64]$BroadcastInteger
    )
    $ip = $null
    if (-not [System.Net.IPAddress]::TryParse([string]$Neighbor.ipv4,[ref]$ip)) { return $false }
    if ($ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { return $false }
    $value = ConvertTo-SasIPv4Integer -Address $ip
    return $value -gt $NetworkInteger -and $value -lt $BroadcastInteger
}

function Test-SasNeighborUsable {
    param([Parameter(Mandatory=$true)][object]$Neighbor)
    return [string]$Neighbor.state -in @('Reachable','Delay','Probe','Permanent')
}

if (-not $ConfirmConsumerLab) {
    throw 'HOME_LAB_CONFIRMATION_REQUIRED: rerun through Discover-HHCCReaderHomeLab.cmd with explicit CONFIRM_CONSUMER_LAB.'
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runtimeRoot = [IO.Path]::GetFullPath('C:\SASAL').TrimEnd('\')
$currentRoot = [IO.Path]::GetFullPath($repoRoot).TrimEnd('\')
if (-not $currentRoot.Equals($runtimeRoot,[StringComparison]::OrdinalIgnoreCase)) {
    throw ("SEALED_RUNTIME_REQUIRED: discovery must execute from C:\SASAL; current root is {0}." -f $currentRoot)
}

$outputRoot = Join-Path $repoRoot 'survey\output\hh-cc-reader'
[void](New-Item -ItemType Directory -Force -Path $outputRoot)

$stateRootBase = if ([string]::IsNullOrWhiteSpace($env:ProgramData)) { $env:TEMP } else { $env:ProgramData }
$stateRoot = Join-Path $stateRootBase 'SysAdminSuite\hh-cc-reader'
$safeRunId = ($RunId -replace '[^A-Za-z0-9_.-]','_')
$statePath = Join-Path $stateRoot ("home-lab-state-{0}.json" -f $safeRunId)
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw 'HOME_LAB_PREPARE_STATE_REQUIRED: run Prepare-HHCCReaderNetworkSwitch.cmd for this RUN_ID before changing networks.'
}

try {
    $preparedState = Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
} catch {
    throw ("HOME_LAB_PREPARE_STATE_INVALID: {0}" -f $_.Exception.Message)
}
if ([string]$preparedState.run_id -ne $RunId) {
    throw 'HOME_LAB_PREPARE_STATE_RUN_ID_MISMATCH.'
}
if ([string]::IsNullOrWhiteSpace([string]$preparedState.prepared_commit)) {
    throw 'HOME_LAB_PREPARED_COMMIT_MISSING.'
}
if ([string]::IsNullOrWhiteSpace([string]$preparedState.before_checkpoint)) {
    throw 'HOME_LAB_BEFORE_SWITCH_CHECKPOINT_MISSING.'
}

$currentCommit = Get-SasRepoCommit -Root $repoRoot
if ($currentCommit -ne [string]$preparedState.prepared_commit) {
    throw ("SEALED_RUNTIME_COMMIT_MISMATCH: prepared {0}; executing {1}." -f $preparedState.prepared_commit,$currentCommit)
}

$stateMac = $null
if (-not [string]::IsNullOrWhiteSpace([string]$preparedState.expected_mac)) {
    $stateMac = ConvertTo-SasNormalizedMac -Value ([string]$preparedState.expected_mac)
}
$normalizedExpectedMac = ConvertTo-SasNormalizedMac -Value $ExpectedMac
if ($normalizedExpectedMac -and $stateMac -and $normalizedExpectedMac -ne $stateMac) {
    throw 'EXPECTED_MAC_CONFLICTS_WITH_PREPARED_STATE.'
}
if (-not $normalizedExpectedMac) { $normalizedExpectedMac = $stateMac }
if (-not $normalizedExpectedMac) {
    throw 'Expected MAC is required for identity-safe home-lab discovery. Prepare the run with an approved expected MAC.'
}

$sessionModule = Join-Path $repoRoot 'scripts\SasOperatorSession.psm1'
if (-not (Test-Path -LiteralPath $sessionModule -PathType Leaf)) {
    throw 'HOME_LAB_NETWORK_CLASSIFIER_MISSING.'
}
Import-Module $sessionModule -Force -ErrorAction Stop
$network = Get-SasOperatorNetworkClassification -RepoRoot $repoRoot
if ([string]$network.classification -ne 'GUEST_INTERNET') {
    throw ("HOME_LAB_NETWORK_AUTHORITY_REJECTED: current classification is {0} [{1}]. No local-subnet discovery was run." -f $network.classification,$network.label)
}

$beforeReceipt = $null
try {
    $beforeReceipt = Get-Content -LiteralPath ([string]$preparedState.before_checkpoint) -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
} catch {
    throw ("HOME_LAB_BEFORE_SWITCH_RECEIPT_UNREADABLE: {0}" -f $_.Exception.Message)
}

$checkpoint = Join-Path $PSScriptRoot 'Invoke-SasHhCcReaderNetworkCheckpoint.ps1'
if (-not (Test-Path -LiteralPath $checkpoint -PathType Leaf)) {
    throw 'AFTER_SWITCH checkpoint implementation is missing.'
}
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $checkpoint -Phase AFTER_SWITCH -RunId $RunId -ExpectedMac $normalizedExpectedMac -Label 'authorized-consumer-lab'
if ($LASTEXITCODE -ne 0) { throw 'AFTER_SWITCH checkpoint failed; discovery did not start.' }

$routes = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
    Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' } |
    Sort-Object RouteMetric,InterfaceIndex)
if ($routes.Count -eq 0) { throw 'No active IPv4 default route was found.' }

$selectedRoute = $null
$selectedAddress = $null
$selectedConfig = $null
foreach ($route in $routes) {
    $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.InterfaceIndex -ErrorAction Stop |
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
            $selectedConfig = Get-NetIPConfiguration -InterfaceIndex $route.InterfaceIndex -ErrorAction Stop
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

$gatewayIp = $null
if (-not [System.Net.IPAddress]::TryParse([string]$selectedRoute.NextHop,[ref]$gatewayIp) -or -not (Test-SasPrivateIPv4 -Address $gatewayIp)) {
    throw 'HOME_LAB_PRIVATE_GATEWAY_REQUIRED: selected default gateway is not private IPv4.'
}

$localInteger = ConvertTo-SasIPv4Integer -Address $localIp
$blockSize = [uint64][math]::Pow(2,(32 - $prefixLength))
$networkInteger = [uint64]([math]::Floor($localInteger / $blockSize) * $blockSize)
$broadcastInteger = $networkInteger + $blockSize - 1
$hostCount64 = [uint64]($blockSize - 2)
if ($hostCount64 -gt [uint64]$MaxHosts) {
    throw ("HOME_LAB_SCOPE_TOO_LARGE: current /{0} contains {1} host addresses; limit is {2}. No active discovery was run." -f $prefixLength,$hostCount64,$MaxHosts)
}
$hostCount = [int]$hostCount64

$beforePrimary = @($beforeReceipt.active_ipv4 | Where-Object {
    -not [string]::IsNullOrWhiteSpace([string]$_.ipv4)
} | Select-Object -First 1)
$beforeGateway = @($beforeReceipt.default_routes | Where-Object {
    -not [string]::IsNullOrWhiteSpace([string]$_.next_hop)
} | Select-Object -First 1)
$networkChangedFromBefore = $true
if ($beforePrimary.Count -eq 1 -and $beforeGateway.Count -eq 1) {
    $networkChangedFromBefore = -not (
        [string]$beforePrimary[0].ipv4 -eq $localIp.ToString() -and
        [int]$beforePrimary[0].prefix_length -eq $prefixLength -and
        [string]$beforeGateway[0].next_hop -eq [string]$selectedRoute.NextHop
    )
}

$before = Get-SasNeighbors -InterfaceIndex ([int]$selectedRoute.InterfaceIndex)
$exactBefore = @($before | Where-Object {
    $_.mac -eq $normalizedExpectedMac -and
    (Test-SasNeighborInCurrentSubnet -Neighbor $_ -NetworkInteger $networkInteger -BroadcastInteger $broadcastInteger) -and
    (Test-SasNeighborUsable -Neighbor $_)
})
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

Start-Sleep -Milliseconds 1000
$after = Get-SasNeighbors -InterfaceIndex ([int]$selectedRoute.InterfaceIndex)
$exactAfter = @($after | Where-Object {
    $_.mac -eq $normalizedExpectedMac -and
    (Test-SasNeighborInCurrentSubnet -Neighbor $_ -NetworkInteger $networkInteger -BroadcastInteger $broadcastInteger) -and
    (Test-SasNeighborUsable -Neighbor $_)
})
$expectedOui = (($normalizedExpectedMac -replace '-','').Substring(0,6))
$sameOui = @($after | Where-Object {
    $_.mac.Length -ge 8 -and
    (($_.mac -replace '-','').Substring(0,6)) -eq $expectedOui -and
    $_.mac -ne $normalizedExpectedMac -and
    (Test-SasNeighborInCurrentSubnet -Neighbor $_ -NetworkInteger $networkInteger -BroadcastInteger $broadcastInteger) -and
    (Test-SasNeighborUsable -Neighbor $_)
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

$stamp = [DateTimeOffset]::Now.ToString('yyyyMMdd-HHmmss-fff')
$suffix = [Guid]::NewGuid().ToString('N').Substring(0,8)
$result = [ordered]@{
    schema_version = 'sas-hh-cc-reader-home-lab-discovery/v1'
    timestamp = [DateTimeOffset]::Now.ToString('o')
    run_id = $RunId
    network_environment = 'AUTHORIZED_CONSUMER_LAB'
    operator_confirmed_consumer_lab = $true
    network_classification = [string]$network.classification
    network_label = [string]$network.label
    prepared_commit = [string]$preparedState.prepared_commit
    executing_commit = $currentCommit
    prepared_commit_verified = $true
    before_switch_checkpoint = [string]$preparedState.before_checkpoint
    network_changed_from_before = $networkChangedFromBefore
    source_interface = [ordered]@{
        interface_index = [int]$selectedRoute.InterfaceIndex
        interface_alias = [string]$selectedConfig.InterfaceAlias
        network_profile = [string]$selectedConfig.NetProfile.Name
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

$receiptPath = Join-Path $outputRoot ("hh-cc-reader-home-lab-discovery-{0}-{1}.json" -f $stamp,$suffix)
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $receiptPath -Encoding UTF8

Write-Host ("CLASSIFICATION={0}" -f $classification)
Write-Host ("NETWORK_AUTHORITY={0} [{1}]" -f $network.classification,$network.label)
Write-Host ("PREPARED_COMMIT_VERIFIED={0}" -f $currentCommit)
Write-Host ("NETWORK_CHANGED_FROM_BEFORE={0}" -f $networkChangedFromBefore)
Write-Host ("EVIDENCE={0}" -f $receiptPath)
if (-not $targetIp -and $sameOui.Count -gt 0) {
    Write-Host ("SAME_OUI_CANDIDATES={0}" -f $sameOui.Count)
    Write-Host 'NOTE: same-OUI candidates are not promoted to reader identity without stronger corroboration.'
}
if ($classification -eq 'HOME_LAB_EXACT_MAC_AMBIGUOUS') { exit 5 }
if ($targetIp -and $probeExit -ne 0) { exit $probeExit }
exit 0
