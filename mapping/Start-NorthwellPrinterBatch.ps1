<#
.SYNOPSIS
    Batch technician front-end for reversible Northwell printer management.

.DESCRIPTION
    Reads mapping\NorthwellPrinterBatch.csv. Each CSV row is one explicit group:
      Action       - optional Map or Unmap; defaults to Map for older local files
      ComputerName - one or more target hostnames separated with semicolons
      PrintServer  - one print-server hostname, or blank for full UNC/AD lookup
      QueueName    - one or more queue names separated with semicolons

    Local shape validation occurs before network activity. Full queue resolution
    requires approved Northwell network authority. Before live mutation the full
    mixed map/unmap plan is shown and exact APPLY confirmation is required unless
    -ConfirmBatch is supplied by an advanced operator.
#>

[CmdletBinding()]
param(
    [string]$BatchFile,
    [switch]$WhatIf,
    [switch]$ConfirmBatch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($BatchFile)) { $BatchFile = Join-Path $PSScriptRoot 'NorthwellPrinterBatch.csv' }
$BatchFile = [System.IO.Path]::GetFullPath($BatchFile)
$exampleFile = Join-Path $PSScriptRoot 'Examples\NorthwellPrinterBatch.example.csv'
$latestPath = Join-Path (Join-Path $PSScriptRoot 'Logs') 'LATEST-PATH.txt'

if (-not (Test-Path -LiteralPath $BatchFile -PathType Leaf)) {
    if (-not (Test-Path -LiteralPath $exampleFile -PathType Leaf)) { throw "Batch file is missing and the tracked example could not be found: $exampleFile" }
    Copy-Item -LiteralPath $exampleFile -Destination $BatchFile -Force
    Write-Host ''
    Write-Host 'A local batch file was created from the tracked synthetic example:' -ForegroundColor Yellow
    Write-Host "  $BatchFile" -ForegroundColor Cyan
    Write-Host 'Replace every REPLACE-WITH-* value, choose Map or Unmap, save, then run the batch CMD again.' -ForegroundColor Yellow
    Start-Process -FilePath 'notepad.exe' -ArgumentList @($BatchFile) | Out-Null
    exit 2
}

$modulePath = Join-Path $PSScriptRoot 'Modules\NorthwellPrinterMapping.Core.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "Northwell printer core module not found: $modulePath" }
Import-Module $modulePath -Force -ErrorAction Stop

$rows = @(Import-Csv -LiteralPath $BatchFile)
$null = @(ConvertTo-SasNorthwellPrinterBatchGroups -Rows $rows -ShapeOnly)

$authorityModule = Join-Path $repoRoot 'scripts\SasNorthwellNetworkAuthority.psm1'
if (-not (Test-Path -LiteralPath $authorityModule -PathType Leaf)) { throw "Northwell network authority module not found: $authorityModule" }
Import-Module $authorityModule -Force -ErrorAction Stop
$authority = Assert-SasNorthwellNetwork
Write-Host ("Approved Northwell network authority: {0} ({1})" -f $authority.Route,$authority.Evidence) -ForegroundColor Green
Write-Host 'WAB Wi-Fi, approved hardwire, and authenticated VPN are all valid controller paths when the shared guard proves authority.' -ForegroundColor Green

$groups = @(ConvertTo-SasNorthwellPrinterBatchGroups -Rows $rows)
if ($groups.Count -eq 0) { throw 'Batch plan contains no printer-management groups.' }

$engine = Join-Path $PSScriptRoot 'Invoke-NorthwellPrinterState.ps1'
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw "Canonical reversible printer engine not found: $engine" }

$runToken = New-SasNorthwellPrinterRunToken
$sessionRoot = Join-Path (Join-Path $PSScriptRoot 'Logs') "NorthwellPrinterBatch-$runToken"
New-Item -ItemType Directory -Path $sessionRoot -Force | Out-Null
$planPath = Join-Path $sessionRoot 'BatchPlan.json'
$summaryPath = Join-Path $sessionRoot 'Summary.json'
$undoPath = Join-Path $sessionRoot 'UndoPlan.json'
$results = New-Object System.Collections.Generic.List[object]
$undoEntries = New-Object System.Collections.Generic.List[object]

[ordered]@{
    SchemaVersion = 'sas-northwell-printer-batch/v2'
    RunToken = $runToken
    BatchFileName = [System.IO.Path]::GetFileName($BatchFile)
    WhatIf = [bool]$WhatIf
    GroupCount = $groups.Count
    Groups = $groups
    NetworkRoute = $authority.Route
    Created = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding UTF8

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' NORTHWELL REVERSIBLE PRINTER BATCH PLAN' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Batch file: $BatchFile"
Write-Host "Groups    : $($groups.Count)"
foreach ($group in $groups) {
    Write-Host ("Row {0}: {1} {2} -> {3}" -f $group.RowNumber,$group.Action,($group.Computers -join ', '),($group.Printers -join ', '))
}
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Plan artifact: $planPath" -ForegroundColor DarkGray
Write-Host ''

if (-not $WhatIf -and -not $ConfirmBatch) {
    $confirmation = Read-Host 'Type APPLY to execute this exact map/unmap batch plan'
    if ($confirmation -cne 'APPLY') {
        Write-Host 'CANCELLED: no printer state was changed.' -ForegroundColor Yellow
        exit 3
    }
}

$groupIndex = 0
foreach ($group in $groups) {
    $groupIndex++
    $groupRoot = Join-Path $sessionRoot ('Group-{0:D3}' -f $groupIndex)
    $desiredState = if ($group.Action -eq 'Map') { 'Present' } else { 'Absent' }
    $invoke = @{
        ComputerName = @($group.Computers)
        Printer = @($group.Printers)
        DesiredState = $desiredState
        SessionRoot = $groupRoot
    }
    if ($WhatIf) { $invoke.WhatIf = $true }

    $success = $false
    $message = ''
    try {
        Write-Host ("Running batch group {0}/{1}: {2}..." -f $groupIndex,$groups.Count,$group.Action) -ForegroundColor Cyan
        & $engine @invoke
        if ($WhatIf) {
            $success = $true
            $message = 'PLAN_ONLY'
        }
        else {
            $childSummaryPath = Join-Path $groupRoot 'Summary.json'
            if (-not (Test-Path -LiteralPath $childSummaryPath -PathType Leaf)) { throw "Canonical engine did not produce Summary.json for batch group $groupIndex." }
            $childSummary = Get-Content -LiteralPath $childSummaryPath -Raw | ConvertFrom-Json
            $success = [bool]$childSummary.Success
            $message = if ($success) { "MACHINE_WIDE_$($desiredState.ToUpperInvariant())_PROVED" } else { 'ENGINE_SUMMARY_FAILED' }
        }
    }
    catch {
        $success = $false
        $message = $_.Exception.Message
        Write-Host "Batch group $groupIndex failed: $message" -ForegroundColor Red
    }

    $childUndoPath = Join-Path $groupRoot 'UndoPlan.json'
    if (Test-Path -LiteralPath $childUndoPath -PathType Leaf) {
        try {
            $childUndo = Get-Content -LiteralPath $childUndoPath -Raw | ConvertFrom-Json
            foreach ($entry in @($childUndo.Entries)) { $undoEntries.Add($entry) }
        }
        catch { Write-Host "WARN: could not aggregate undo plan for group ${groupIndex}: $($_.Exception.Message)" -ForegroundColor Yellow }
    }

    $results.Add([pscustomobject][ordered]@{
        Group = $groupIndex
        SourceRow = $group.RowNumber
        Action = $group.Action
        DesiredState = $desiredState
        Computers = @($group.Computers)
        Printers = @($group.Printers)
        Success = $success
        Message = $message
        Evidence = $groupRoot
    })
}

[ordered]@{
    SchemaVersion = 'sas-northwell-printer-undo/v1'
    SourceRunToken = $runToken
    SourceSessionRoot = $sessionRoot
    SourceAction = 'Batch'
    EntryCount = $undoEntries.Count
    Entries = $undoEntries.ToArray()
    Created = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $undoPath -Encoding UTF8

$failed = @($results | Where-Object { -not $_.Success })
$summary = [ordered]@{
    SchemaVersion = 'sas-northwell-printer-batch/v2'
    RunToken = $runToken
    Success = ($failed.Count -eq 0)
    Mode = 'NorthwellPrinterBatch'
    ProofLevel = if ($WhatIf) { 'PLAN_ONLY' } else { 'MACHINE_WIDE_DESIRED_STATE' }
    RuntimePrintObservedByEngine = $false
    TestPagesPrinted = $false
    BatchFileName = [System.IO.Path]::GetFileName($BatchFile)
    TotalGroups = $groups.Count
    CompletedGroups = $results.Count
    FailedGroups = $failed.Count
    Results = $results.ToArray()
    BatchPlan = $planPath
    UndoPlan = $undoPath
    SessionRoot = $sessionRoot
    Updated = (Get-Date).ToString('o')
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$sessionRoot | Set-Content -LiteralPath $latestPath -Encoding UTF8

Write-Host ''
if ($summary.Success) {
    if ($WhatIf) { Write-Host 'PASS: batch plan resolved. No remote printer state was changed.' -ForegroundColor Green }
    else { Write-Host 'PASS: every batch group returned requested machine-wide state proof.' -ForegroundColor Green }
}
else { Write-Host "FAIL: $($failed.Count) batch group(s) failed. Evidence and any observed undo transitions were preserved." -ForegroundColor Red }
Write-Host "Evidence : $sessionRoot" -ForegroundColor Cyan
Write-Host "Undo plan: $undoPath" -ForegroundColor Cyan

if (-not $summary.Success) { throw "Northwell printer batch failed in $($failed.Count) group(s). Review $summaryPath" }
