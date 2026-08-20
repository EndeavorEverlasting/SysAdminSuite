#Requires -Version 5.1
<#
.SYNOPSIS
    Finalizes active-user printer connections for successful Map rows in a reversible batch.

.DESCRIPTION
    Reads the latest successful Northwell batch evidence, skips Unmap rows, and invokes
    the canonical active-user finalizer only for successful Map groups. This prevents a
    mixed reversible batch from reconnecting a printer that the same batch intentionally
    removed while preserving immediate active-user verification for mapped queues.
#>

[CmdletBinding()]
param(
    [string]$EvidenceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$latestPointer = Join-Path $PSScriptRoot 'Logs\LATEST-PATH.txt'
$finalizer = Join-Path $PSScriptRoot 'Confirm-NorthwellPrinterActiveUserMaterialization.ps1'
if (-not (Test-Path -LiteralPath $finalizer -PathType Leaf)) { throw "Active-user printer finalizer not found: $finalizer" }

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    if (-not (Test-Path -LiteralPath $latestPointer -PathType Leaf)) { throw "Latest printer evidence pointer not found: $latestPointer" }
    $EvidenceRoot = ([string](Get-Content -LiteralPath $latestPointer -Raw -ErrorAction Stop)).Trim()
}
if ([string]::IsNullOrWhiteSpace($EvidenceRoot) -or -not (Test-Path -LiteralPath $EvidenceRoot -PathType Container)) {
    throw "Printer batch evidence root does not exist: $EvidenceRoot"
}
$EvidenceRoot = [System.IO.Path]::GetFullPath($EvidenceRoot)

$summaryPath = Join-Path $EvidenceRoot 'Summary.json'
if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { throw "Batch Summary.json not found: $summaryPath" }
$summary = Get-Content -LiteralPath $summaryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
if ([string]$summary.Mode -ne 'NorthwellPrinterBatch') { throw "Expected NorthwellPrinterBatch evidence, found: $($summary.Mode)" }
if (-not [bool]$summary.Success) { throw 'Active-user batch finalization requires an already successful machine-wide batch run.' }

$aggregate = New-Object System.Collections.Generic.List[object]
$mapGroups = 0
$skippedUnmapGroups = 0
$failedMapGroups = 0

foreach ($result in @($summary.Results)) {
    $action = 'Map'
    if ($null -ne $result.PSObject.Properties['Action'] -and -not [string]::IsNullOrWhiteSpace([string]$result.Action)) {
        $action = [string]$result.Action
    }

    if (-not $action.Equals('Map',[System.StringComparison]::OrdinalIgnoreCase)) {
        $skippedUnmapGroups++
        continue
    }
    if (-not [bool]$result.Success) { throw "Batch Map group $($result.Group) lacks successful machine-wide proof." }

    $mapGroups++
    $groupRoot = [string]$result.Evidence
    try {
        & $finalizer -EvidenceRoot $groupRoot
        $childPath = Join-Path $groupRoot 'ActiveUserMaterialization.json'
        if (-not (Test-Path -LiteralPath $childPath -PathType Leaf)) { throw "Map group finalizer did not produce: $childPath" }
        $child = Get-Content -LiteralPath $childPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $aggregate.Add([pscustomobject][ordered]@{
            Group = $result.Group
            Success = [bool]$child.Success
            Evidence = $childPath
            Results = @($child.Results)
        })
        if (-not [bool]$child.Success) { $failedMapGroups++ }
    }
    catch {
        $failedMapGroups++
        $aggregate.Add([pscustomobject][ordered]@{
            Group = $result.Group
            Success = $false
            Evidence = $groupRoot
            Error = $_.Exception.Message
            Results = @()
        })
    }
}

$allResults = @($aggregate | ForEach-Object { @($_.Results) })
$materialized = @($allResults | Where-Object { $_.Success -and $_.Materialized }).Count
$pending = @($allResults | Where-Object { $_.Success -and $_.PendingNextLogon }).Count
$failedTargets = @($allResults | Where-Object { -not $_.Success }).Count
$batchFinalizationPath = Join-Path $EvidenceRoot 'ActiveUserMaterialization.json'

[ordered]@{
    SchemaVersion = 'sas-northwell-printer-batch-active-user/v1'
    Success = ($failedMapGroups -eq 0)
    MapGroupsFinalized = $mapGroups
    SkippedUnmapGroups = $skippedUnmapGroups
    FailedMapGroups = $failedMapGroups
    MaterializedTargets = $materialized
    PendingNextLogonTargets = $pending
    FailedTargets = $failedTargets
    TestPagesPrinted = $false
    DirectIpMapping = $false
    Groups = $aggregate.ToArray()
    Updated = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $batchFinalizationPath -Encoding UTF8

Write-Host ''
if ($mapGroups -eq 0) {
    Write-Host 'READY: batch contained no Map groups; active-user materialization was correctly skipped.' -ForegroundColor Green
}
elseif ($failedMapGroups -eq 0) {
    Write-Host ("READY: finalized active-user availability for {0} Map group(s); skipped {1} Unmap group(s)." -f $mapGroups,$skippedUnmapGroups) -ForegroundColor Green
}
else {
    Write-Host ("FAIL: active-user finalization failed for {0} Map group(s)." -f $failedMapGroups) -ForegroundColor Red
}
Write-Host ("Batch active-user evidence: {0}" -f $batchFinalizationPath) -ForegroundColor DarkGray

if ($failedMapGroups -gt 0) {
    throw "Machine-wide batch state succeeded, but active-user finalization failed for $failedMapGroups Map group(s)."
}
