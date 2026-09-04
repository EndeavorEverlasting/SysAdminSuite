#Requires -Version 5.1
<#
.SYNOPSIS
Run a bounded, read-only Cybernet identity canary against explicit approved candidates.

.DESCRIPTION
The canary reduces unnecessary network traffic; it is not a monitoring-evasion feature.
It accepts at most five explicit hostname/FQDN/IP candidates, rejects ranges/CIDRs/wildcards,
reuses completed canary evidence from the previous 24 hours, performs one canonical network
preflight narrowed to TCP 135 for remaining candidates, and attempts one DCOM/CIM identity session
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

function Get-SasFreshCanaryEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$TargetName,
        [Parameter(Mandatory = $true)][datetime]$Cutoff
    )

    if (-not (Test-Path -LiteralPath $outputRoot -PathType Container)) { return $null }
    $markers = @(Get-ChildItem -LiteralPath $outputRoot -Filter 'cybernet_canary_complete.json' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending)
    foreach ($marker in $markers) {
        try { $completion = Get-Content -LiteralPath $marker.FullName -Raw | ConvertFrom-Json } catch { continue }
        if ($completion.completed -ne $true -or [string]::IsNullOrWhiteSpace([string]$completion.result_sha256)) { continue }
        $resultPath = Join-Path $marker.DirectoryName 'cybernet_canary_identity.csv'
        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { continue }
        try { $actualHash = (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash } catch { continue }
        if (-not $actualHash.Equals([string]$completion.result_sha256, [StringComparison]::OrdinalIgnoreCase)) { continue }

        foreach ($row in @(Import-Csv -LiteralPath $resultPath -ErrorAction SilentlyContinue)) {
            if ([string]::IsNullOrWhiteSpace([string]$row.Target) -or -not ([string]$row.Target).Equals($TargetName, [StringComparison]::OrdinalIgnoreCase)) { continue }
            if ([string]::IsNullOrWhiteSpace([string]$row.ObservationTimestamp)) { continue }
            try { $observedAt = [datetime]$row.ObservationTimestamp } catch { continue }
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
$completionPath = Join-Path $runRoot 'cybernet_canary_complete.json'
$targetFile = Join-Path $targetRoot ("cybernet_canary_${runId}_${nonce}.txt")

$cutoff = (Get-Date).AddHours(-1 * $ReuseWithinHours)
$results = New-Object 'System.Collections.Generic.List[object]'
$liveTargets = New-Object 'System.Collections.Generic.List[string]'

foreach ($candidate in $targets) {
    $fresh = Get-SasFreshCanaryEvidence -TargetName $candidate -Cutoff $cutoff
    if ($null -ne $fresh) {
        $results.Add([pscustomobject]@{
            Timestamp = (Get-Date).ToString('o')
            ObservationTimestamp = [string]$fresh.ObservationTimestamp
            Target = $candidate
            ResolvedAddress = [string]$fresh.ResolvedAddress
            PingStatus = [string]$fresh.PingStatus
            Port135 = [string]$fresh.Port135
            ObservedHostName = [string]$fresh.ObservedHostName
            ObservedManufacturer = [string]$fresh.ObservedManufacturer
            ObservedModel = [string]$fresh.ObservedModel
            ObservedSerial = [string]$fresh.ObservedSerial
            IdentityStatus = [string]$fresh.IdentityStatus
            EvidenceSource = 'FreshLocalReuse'
            NetworkActivityPerformed = $false
            Notes = "Reused completed canary evidence observed within $ReuseWithinHours hours (source status: $([string]$fresh.IdentityStatus)); no live probe performed."
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
        & $preflight -TargetFile $targetFile -Ports @(135) -PolicyProfile 'network_preflight' -OutputDirectory $preflightRoot
        $preflightCsv = @(Get-ChildItem -LiteralPath $preflightRoot -Filter 'network_preflight_*.csv' -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
        if ($preflightCsv.Count -ne 1) { throw 'Canary preflight did not produce exactly one network_preflight CSV.' }
        $preflightRows = @(Import-Csv -LiteralPath $preflightCsv[0].FullName)
    }

    foreach ($candidate in $liveTargets) {
        $rows = @($preflightRows | Where-Object { ([string]$_.Target).Equals($candidate, [StringComparison]::OrdinalIgnoreCase) })
        $firstRow = $rows | Select-Object -First 1
        $resolved = if ($null -ne $firstRow) { [string]$firstRow.ResolvedAddress } else { '' }
        $pingStatus = if ($null -ne $firstRow) { [string]$firstRow.PingStatus } else { '' }
        $port135Row = $rows | Where-Object { [int]$_.Port -eq 135 } | Select-Object -First 1
        $port135 = if ($null -ne $port135Row) { [string]$port135Row.PortStatus } else { 'NotChecked' }
        $identityEndpoint = if (-not [string]::IsNullOrWhiteSpace($resolved)) { $resolved } else { $candidate }

        $observationTimestamp = (Get-Date).ToString('o')
        $observedHost = ''
        $manufacturer = ''
        $model = ''
        $serial = ''
        $identityStatus = 'RPC_NOT_OPEN_IDENTITY_SKIPPED'
        $noteParts = New-Object 'System.Collections.Generic.List[string]'
        [void]$noteParts.Add('TCP 135 did not earn a DCOM/CIM identity query.')

        if ($port135 -eq 'Open') {
            $noteParts.Clear()
            $session = $null
            try {
                $sessionOption = New-CimSessionOption -Protocol Dcom
                $session = New-CimSession -ComputerName $identityEndpoint -SessionOption $sessionOption -ErrorAction Stop
            } catch {
                [void]$noteParts.Add('Read-only DCOM/CIM session creation failed or was denied; no retry performed.')
            }

            if ($null -ne $session) {
                try {
                    $computer = Get-CimInstance -CimSession $session -ClassName Win32_ComputerSystem -Property Name,Manufacturer,Model -OperationTimeoutSec 8 -ErrorAction Stop | Select-Object -First 1
                    if ($null -ne $computer) {
                        $observedHost = [string]$computer.Name
                        $manufacturer = [string]$computer.Manufacturer
                        $model = [string]$computer.Model
                    }
                } catch {
                    [void]$noteParts.Add('Win32_ComputerSystem identity query failed or was denied.')
                }

                try {
                    $bios = Get-CimInstance -CimSession $session -ClassName Win32_BIOS -Property SerialNumber -OperationTimeoutSec 8 -ErrorAction Stop | Select-Object -First 1
                    if ($null -ne $bios) { $serial = [string]$bios.SerialNumber }
                } catch {
                    [void]$noteParts.Add('Win32_BIOS serial query failed or was denied.')
                }
                Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue
            }

            if (-not [string]::IsNullOrWhiteSpace($model) -and -not [string]::IsNullOrWhiteSpace($serial)) {
                $identityStatus = 'IDENTITY_COLLECTED'
                [void]$noteParts.Add('One read-only DCOM/CIM session returned model and BIOS serial.')
            } elseif (-not [string]::IsNullOrWhiteSpace($observedHost) -or -not [string]::IsNullOrWhiteSpace($manufacturer) -or -not [string]::IsNullOrWhiteSpace($model) -or -not [string]::IsNullOrWhiteSpace($serial)) {
                $identityStatus = 'IDENTITY_PARTIAL'
                [void]$noteParts.Add('Partial hardware identity was retained; no retry performed.')
            } else {
                $identityStatus = 'IDENTITY_QUERY_FAILED'
            }
        }

        $results.Add([pscustomobject]@{
            Timestamp = (Get-Date).ToString('o')
            ObservationTimestamp = $observationTimestamp
            Target = $candidate
            ResolvedAddress = $resolved
            PingStatus = $pingStatus
            Port135 = $port135
            ObservedHostName = $observedHost
            ObservedManufacturer = $manufacturer
            ObservedModel = $model
            ObservedSerial = $serial
            IdentityStatus = $identityStatus
            EvidenceSource = 'LiveBoundedCanary'
            NetworkActivityPerformed = $true
            Notes = ($noteParts -join ' ')
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

$resultHash = (Get-FileHash -LiteralPath $resultCsv -Algorithm SHA256).Hash
$completion = [pscustomobject]@{
    schema_version = 'sas-cybernet-canary-completion/v1'
    completed = $true
    completed_at = (Get-Date).ToString('o')
    result_sha256 = $resultHash
}
$completionTemp = $completionPath + '.tmp'
$completion | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $completionTemp -Encoding UTF8
Move-Item -LiteralPath $completionTemp -Destination $completionPath -Force

Write-Host ''
Write-Host 'Cybernet low-noise identity canary' -ForegroundColor Cyan
Write-Host 'Terminal contract: invoke through the installed sas command from Windows PowerShell; current directory is irrelevant.'
Write-Host "Targets: $($targets.Count) (hard cap: $MaxTargets)"
Write-Host "Fresh completed evidence reused without packets: $($summary.fresh_reuse_count)"
Write-Host "Live bounded canaries: $($summary.live_canary_count)"
Write-Host 'Traffic contract: explicit candidates only; DNS + one ICMP attempt + TCP 135; no canary retry; one DCOM/CIM session only after 135 opens.'
Write-Host 'Monitoring contract: this reduces unnecessary traffic but does not hide activity or guarantee that normal monitoring will not alert.' -ForegroundColor Yellow
Write-Host "Result: $resultCsv" -ForegroundColor Green
Write-Host "Summary: $summaryJson"
Write-Host "Completion marker: $completionPath"
$ordered | Select-Object Target,ObservedManufacturer,ObservedModel,ObservedSerial,IdentityStatus,EvidenceSource | Format-Table -AutoSize
