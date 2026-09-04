#Requires -Version 5.1
<#
.SYNOPSIS
Run a bounded, read-only Cybernet identity canary against explicit approved candidates.

.DESCRIPTION
The canary is designed to reduce unnecessary network traffic, not to evade monitoring.
It accepts at most five explicit hostname/FQDN/IP candidates, rejects ranges/CIDRs/wildcards,
reuses complete identity evidence from the previous 24 hours, performs one canonical network
preflight on TCP 135/445 for remaining candidates, and attempts one DCOM/CIM identity session
only when TCP 135 is open. It never mutates a target and never accepts credentials on the command line.

The result records manufacturer, model, and BIOS serial when the current operator context is allowed
to read them. Model + serial are identity evidence only; this command does not classify a device as Cybernet.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Target,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 168)]
    [int]$ReuseWithinHours = 24
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$preflight = Join-Path $repoRoot 'survey\sas-network-preflight.ps1'
$targetRoot = Join-Path $repoRoot 'targets\local'
$outputRoot = Join-Path $repoRoot 'survey\output\cybernet_canary'
$MaxTargets = 5

if (-not (Test-Path -LiteralPath $preflight -PathType Leaf)) {
    throw "Canonical network preflight is missing: $preflight"
}

function Test-SasExplicitCanaryTarget {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $candidate = $Value.Trim()

    if ($candidate -match '[/*?\[\]]') { return $false }
    if ($candidate -match '^\d{1,3}(?:\.\d{1,3}){3}\s*-\s*\d') { return $false }
    if ($candidate -match '^\d{1,3}(?:\.\d{1,3}){3}\s*-\s*\d{1,3}(?:\.\d{1,3}){3}$') { return $false }
    if ($candidate -match '\.\.') { return $false }

    $ip = $null
    if ([System.Net.IPAddress]::TryParse($candidate, [ref]$ip)) { return $true }
    if ($candidate -match '^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9.-]+$') { return $true }
    if ($candidate -match '^[A-Za-z0-9]+[-_][A-Za-z0-9_-]+$') { return $true }
    if ($candidate -match '^[A-Za-z]{2,6}[0-9]{2,}[A-Za-z0-9_-]*$') { return $true }
    return $false
}

function Get-SasFreshIdentityEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$TargetName,
        [Parameter(Mandatory = $true)][datetime]$Cutoff
    )

    if (-not (Test-Path -LiteralPath $outputRoot -PathType Container)) { return $null }
    $files = @(Get-ChildItem -LiteralPath $outputRoot -Filter 'cybernet_canary_identity.csv' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending)
    foreach ($file in $files) {
        foreach ($row in @(Import-Csv -LiteralPath $file.FullName -ErrorAction SilentlyContinue)) {
            if ([string]::IsNullOrWhiteSpace([string]$row.Target) -or -not ([string]$row.Target).Equals($TargetName, [StringComparison]::OrdinalIgnoreCase)) { continue }
            if ([string]::IsNullOrWhiteSpace([string]$row.ObservedModel) -or [string]::IsNullOrWhiteSpace([string]$row.ObservedSerial)) { continue }
            if ([string]$row.IdentityStatus -ne 'IDENTITY_COLLECTED') { continue }
            try { $observedAt = [datetime]$row.Timestamp } catch { continue }
            if ($observedAt.ToUniversalTime() -lt $Cutoff.ToUniversalTime()) { continue }
            return $row
        }
    }
    return $null
}

$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$targets = New-Object 'System.Collections.Generic.List[string]'
foreach ($rawTarget in @($Target)) {
    $candidate = ([string]$rawTarget).Trim()
    if (-not (Test-SasExplicitCanaryTarget -Value $candidate)) {
        throw "Invalid canary target '$rawTarget'. Use one explicit hostname/FQDN/IP only; CIDRs, ranges, wildcards, and subnet discovery are refused."
    }
    if ($seen.Add($candidate)) { [void]$targets.Add($candidate) }
}

if ($targets.Count -eq 0) { throw 'No explicit Cybernet canary targets were supplied.' }
if ($targets.Count -gt $MaxTargets) {
    throw "CYBERNET_CANARY_SCOPE_EXCEEDED: maximum $MaxTargets explicit candidates per run; received $($targets.Count). Split the approved candidate list into smaller canaries."
}

New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$runId = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$nonce = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$runRoot = Join-Path $outputRoot ("${runId}_${nonce}")
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$resultCsv = Join-Path $runRoot 'cybernet_canary_identity.csv'
$summaryJson = Join-Path $runRoot 'cybernet_canary_summary.json'
$targetFile = Join-Path $targetRoot ("cybernet_canary_${runId}_${nonce}.txt")

$cutoff = (Get-Date).AddHours(-1 * $ReuseWithinHours)
$results = New-Object 'System.Collections.Generic.List[object]'
$liveTargets = New-Object 'System.Collections.Generic.List[string]'

foreach ($candidate in $targets) {
    $fresh = Get-SasFreshIdentityEvidence -TargetName $candidate -Cutoff $cutoff
    if ($null -ne $fresh) {
        $results.Add([pscustomobject]@{
            Timestamp = (Get-Date).ToString('o')
            Target = $candidate
            ResolvedAddress = [string]$fresh.ResolvedAddress
            PingStatus = [string]$fresh.PingStatus
            Port135 = [string]$fresh.Port135
            Port445 = [string]$fresh.Port445
            ObservedHostName = [string]$fresh.ObservedHostName
            ObservedManufacturer = [string]$fresh.ObservedManufacturer
            ObservedModel = [string]$fresh.ObservedModel
            ObservedSerial = [string]$fresh.ObservedSerial
            IdentityStatus = 'IDENTITY_COLLECTED'
            EvidenceSource = 'FreshLocalReuse'
            NetworkActivityPerformed = $false
            Notes = "Reused complete identity evidence within $ReuseWithinHours hours; no live probe performed."
        })
    } else {
        [void]$liveTargets.Add($candidate)
    }
}

$preflightRows = @()
try {
    if ($liveTargets.Count -gt 0) {
        $liveTargets | Set-Content -LiteralPath $targetFile -Encoding UTF8
        $preflightRoot = Join-Path $runRoot 'preflight'
        & $preflight -TargetFile $targetFile -Ports @(135, 445) -PolicyProfile 'network_preflight' -OutputDirectory $preflightRoot
        if ($LASTEXITCODE -ne 0) { throw "Canonical network preflight exited $LASTEXITCODE" }
        $preflightCsv = @(Get-ChildItem -LiteralPath $preflightRoot -Filter 'network_preflight_*.csv' -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
        if ($preflightCsv.Count -ne 1) { throw 'Canary preflight did not produce exactly one network_preflight CSV.' }
        $preflightRows = @(Import-Csv -LiteralPath $preflightCsv[0].FullName)
    }

    foreach ($candidate in $liveTargets) {
        $rows = @($preflightRows | Where-Object { ([string]$_.Target).Equals($candidate, [StringComparison]::OrdinalIgnoreCase) })
        $resolved = [string](($rows | Where-Object { $_.ResolvedAddress } | Select-Object -First 1).ResolvedAddress)
        $pingStatus = [string](($rows | Select-Object -First 1).PingStatus)
        $port135 = [string](($rows | Where-Object { [int]$_.Port -eq 135 } | Select-Object -First 1).PortStatus)
        $port445 = [string](($rows | Where-Object { [int]$_.Port -eq 445 } | Select-Object -First 1).PortStatus)

        $observedHost = ''
        $manufacturer = ''
        $model = ''
        $serial = ''
        $identityStatus = 'RPC_NOT_OPEN_IDENTITY_SKIPPED'
        $notes = 'TCP 135 did not earn a DCOM/CIM identity query.'

        if ($port135 -eq 'Open') {
            $session = $null
            try {
                $sessionOption = New-CimSessionOption -Protocol Dcom
                $session = New-CimSession -ComputerName $candidate -SessionOption $sessionOption -ErrorAction Stop
                $computer = Get-CimInstance -CimSession $session -ClassName Win32_ComputerSystem -Property Name,Manufacturer,Model -OperationTimeoutSec 8 -ErrorAction Stop | Select-Object -First 1
                $bios = Get-CimInstance -CimSession $session -ClassName Win32_BIOS -Property SerialNumber -OperationTimeoutSec 8 -ErrorAction Stop | Select-Object -First 1
                $observedHost = [string]$computer.Name
                $manufacturer = [string]$computer.Manufacturer
                $model = [string]$computer.Model
                $serial = [string]$bios.SerialNumber
                if (-not [string]::IsNullOrWhiteSpace($model) -and -not [string]::IsNullOrWhiteSpace($serial)) {
                    $identityStatus = 'IDENTITY_COLLECTED'
                    $notes = 'One read-only DCOM/CIM identity session returned model and BIOS serial.'
                } else {
                    $identityStatus = 'IDENTITY_PARTIAL'
                    $notes = 'Read-only DCOM/CIM query completed but model and/or BIOS serial was empty.'
                }
            } catch {
                $identityStatus = 'IDENTITY_QUERY_FAILED'
                $notes = 'One read-only DCOM/CIM identity attempt failed or was denied; no retry performed.'
            } finally {
                if ($null -ne $session) { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue }
            }
        }

        $results.Add([pscustomobject]@{
            Timestamp = (Get-Date).ToString('o')
            Target = $candidate
            ResolvedAddress = $resolved
            PingStatus = $pingStatus
            Port135 = $port135
            Port445 = $port445
            ObservedHostName = $observedHost
            ObservedManufacturer = $manufacturer
            ObservedModel = $model
            ObservedSerial = $serial
            IdentityStatus = $identityStatus
            EvidenceSource = 'LiveBoundedCanary'
            NetworkActivityPerformed = $true
            Notes = $notes
        })
    }
} finally {
    if (Test-Path -LiteralPath $targetFile -PathType Leaf) {
        Remove-Item -LiteralPath $targetFile -Force -ErrorAction SilentlyContinue
    }
}

$ordered = @($targets | ForEach-Object {
    $name = $_
    $results | Where-Object { ([string]$_.Target).Equals($name, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
})
$ordered | Export-Csv -LiteralPath $resultCsv -NoTypeInformation -Encoding UTF8

$summary = [pscustomobject]@{
    schema_version = 'sas-cybernet-canary-summary/v1'
    generated_at = (Get-Date).ToString('o')
    target_count = $targets.Count
    fresh_reuse_count = @($ordered | Where-Object { $_.EvidenceSource -eq 'FreshLocalReuse' }).Count
    live_canary_count = @($ordered | Where-Object { $_.EvidenceSource -eq 'LiveBoundedCanary' }).Count
    identity_collected_count = @($ordered | Where-Object { $_.IdentityStatus -eq 'IDENTITY_COLLECTED' }).Count
    identity_incomplete_count = @($ordered | Where-Object { $_.IdentityStatus -ne 'IDENTITY_COLLECTED' }).Count
    target_mutation_performed = $false
    stealth_or_evasion_claim = $false
    result_csv = $resultCsv
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $summaryJson -Encoding UTF8

Write-Host ''
Write-Host 'Cybernet low-noise identity canary' -ForegroundColor Cyan
Write-Host 'Terminal contract: invoke through the installed sas command from Windows PowerShell; current directory is irrelevant.'
Write-Host "Targets: $($targets.Count) (hard cap: $MaxTargets)"
Write-Host "Fresh evidence reused without packets: $($summary.fresh_reuse_count)"
Write-Host "Live bounded canaries: $($summary.live_canary_count)"
Write-Host 'Traffic contract: explicit candidates only; one preflight; no retries; one DCOM/CIM identity session only after TCP 135 opens.'
Write-Host 'Monitoring contract: this reduces unnecessary traffic but does not hide activity or guarantee that normal monitoring will not alert.' -ForegroundColor Yellow
Write-Host "Result: $resultCsv" -ForegroundColor Green
Write-Host "Summary: $summaryJson"
$ordered | Select-Object Target,ObservedManufacturer,ObservedModel,ObservedSerial,IdentityStatus,EvidenceSource | Format-Table -AutoSize
