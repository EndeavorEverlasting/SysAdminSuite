<#
.SYNOPSIS
    Reverses the latest observed Northwell printer state transitions.

.DESCRIPTION
    Reads UndoPlan.json from the latest printer evidence directory (or an explicit
    EvidenceRoot). Only transitions recorded by the prior run are eligible. The
    full inverse plan is displayed and exact UNDO confirmation is required before
    live mutation. The undo run writes its own UndoPlan.json, making the undo
    itself reversible when the inverse transition succeeds.
#>

[CmdletBinding()]
param(
    [string]$EvidenceRoot,
    [switch]$ConfirmUndo,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$logsRoot = Join-Path $PSScriptRoot 'Logs'
$latestPath = Join-Path $logsRoot 'LATEST-PATH.txt'

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    if (-not (Test-Path -LiteralPath $latestPath -PathType Leaf)) { throw "Latest printer evidence pointer not found: $latestPath" }
    $EvidenceRoot = (Get-Content -LiteralPath $latestPath -Raw).Trim()
}
$EvidenceRoot = [System.IO.Path]::GetFullPath($EvidenceRoot)
$undoSourcePath = Join-Path $EvidenceRoot 'UndoPlan.json'
if (-not (Test-Path -LiteralPath $undoSourcePath -PathType Leaf)) { throw "Undo plan not found: $undoSourcePath" }

$source = Get-Content -LiteralPath $undoSourcePath -Raw | ConvertFrom-Json
if ([string]$source.SchemaVersion -ne 'sas-northwell-printer-undo/v1') { throw "Unsupported undo schema: $($source.SchemaVersion)" }
$entries = @($source.Entries)
if ($entries.Count -eq 0) {
    Write-Host 'Nothing to undo: the prior run recorded no machine-wide printer state transition.' -ForegroundColor Green
    return
}
foreach ($entry in $entries) {
    if ([string]::IsNullOrWhiteSpace([string]$entry.Computer)) { throw 'Undo plan contains a blank target computer.' }
    if ([string]$entry.DesiredState -notin @('Present','Absent')) { throw "Undo plan contains unsafe DesiredState '$($entry.DesiredState)'." }
    if (@($entry.Printers).Count -eq 0) { throw "Undo plan entry for '$($entry.Computer)' has no printers." }
}

$authorityModule = Join-Path $repoRoot 'scripts\SasNorthwellNetworkAuthority.psm1'
if (-not (Test-Path -LiteralPath $authorityModule -PathType Leaf)) { throw "Northwell network authority module not found: $authorityModule" }
if (-not $WhatIf) {
    Import-Module $authorityModule -Force -ErrorAction Stop
    $authority = Assert-SasNorthwellNetwork
    Write-Host ("Approved Northwell network authority: {0} ({1})" -f $authority.Route,$authority.Evidence) -ForegroundColor Green
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' NORTHWELL PRINTER UNDO PLAN' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Source evidence: $EvidenceRoot"
foreach ($entry in $entries) {
    $action = if ([string]$entry.DesiredState -eq 'Present') { 'MAP' } else { 'UNMAP' }
    Write-Host ("{0}: {1} -> {2}" -f $action,$entry.Computer,(@($entry.Printers) -join ', '))
}
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'Only queues proven to have changed in the source run are included.' -ForegroundColor Green
Write-Host ''

if (-not $WhatIf -and -not $ConfirmUndo) {
    $confirmation = Read-Host 'Type UNDO to execute this exact inverse plan'
    if ($confirmation -cne 'UNDO') {
        Write-Host 'CANCELLED: no printer state was changed.' -ForegroundColor Yellow
        exit 3
    }
}

$modulePath = Join-Path $PSScriptRoot 'Modules\NorthwellPrinterMapping.Core.psm1'
Import-Module $modulePath -Force -ErrorAction Stop
$engine = Join-Path $PSScriptRoot 'Invoke-NorthwellPrinterState.ps1'
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw "Canonical reversible printer engine not found: $engine" }

$runToken = New-SasNorthwellPrinterRunToken
$sessionRoot = Join-Path $logsRoot "NorthwellPrinterUndo-$runToken"
New-Item -ItemType Directory -Path $sessionRoot -Force | Out-Null
$planPath = Join-Path $sessionRoot 'UndoExecutionPlan.json'
$summaryPath = Join-Path $sessionRoot 'Summary.json'
$newUndoPath = Join-Path $sessionRoot 'UndoPlan.json'
$results = New-Object System.Collections.Generic.List[object]
$redoEntries = New-Object System.Collections.Generic.List[object]

[ordered]@{
    SchemaVersion = 'sas-northwell-printer-undo-execution/v1'
    RunToken = $runToken
    SourceEvidenceRoot = $EvidenceRoot
    WhatIf = [bool]$WhatIf
    EntryCount = $entries.Count
    Entries = $entries
    Created = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding UTF8

$index = 0
foreach ($entry in $entries) {
    $index++
    $childRoot = Join-Path $sessionRoot ('Entry-{0:D3}' -f $index)
    $invoke = @{
        ComputerName = @([string]$entry.Computer)
        Printer = @($entry.Printers)
        DesiredState = [string]$entry.DesiredState
        SessionRoot = $childRoot
    }
    if ($WhatIf) { $invoke.WhatIf = $true }
    $success = $false
    $message = ''
    try {
        & $engine @invoke
        $success = $true
        $message = if ($WhatIf) { 'PLAN_ONLY' } else { 'INVERSE_STATE_PROVED' }
    }
    catch {
        $message = $_.Exception.Message
        Write-Host "Undo entry $index failed: $message" -ForegroundColor Red
    }

    $childUndoPath = Join-Path $childRoot 'UndoPlan.json'
    if (Test-Path -LiteralPath $childUndoPath -PathType Leaf) {
        try {
            $childUndo = Get-Content -LiteralPath $childUndoPath -Raw | ConvertFrom-Json
            foreach ($redo in @($childUndo.Entries)) { $redoEntries.Add($redo) }
        }
        catch { Write-Host "WARN: could not aggregate redo transition for entry $index: $($_.Exception.Message)" -ForegroundColor Yellow }
    }

    $results.Add([pscustomobject][ordered]@{
        Entry = $index
        Computer = [string]$entry.Computer
        DesiredState = [string]$entry.DesiredState
        Printers = @($entry.Printers)
        Success = $success
        Message = $message
        Evidence = $childRoot
    })
}

[ordered]@{
    SchemaVersion = 'sas-northwell-printer-undo/v1'
    SourceRunToken = $runToken
    SourceSessionRoot = $sessionRoot
    SourceAction = 'Undo'
    EntryCount = $redoEntries.Count
    Entries = $redoEntries.ToArray()
    Created = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $newUndoPath -Encoding UTF8

$failed = @($results | Where-Object { -not $_.Success })
[ordered]@{
    SchemaVersion = 'sas-northwell-printer-undo-execution/v1'
    RunToken = $runToken
    Success = ($failed.Count -eq 0)
    SourceEvidenceRoot = $EvidenceRoot
    Results = $results.ToArray()
    UndoPlan = $newUndoPath
    SessionRoot = $sessionRoot
    Updated = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$sessionRoot | Set-Content -LiteralPath $latestPath -Encoding UTF8

Write-Host ''
Write-Host "Evidence : $sessionRoot" -ForegroundColor Cyan
Write-Host "Next undo/redo plan: $newUndoPath" -ForegroundColor Cyan
if ($failed.Count -gt 0) { throw "Printer undo failed in $($failed.Count) entry/entries. Review $summaryPath" }
Write-Host 'PASS: every inverse transition returned requested machine-wide state proof.' -ForegroundColor Green
