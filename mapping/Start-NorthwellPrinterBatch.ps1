<#
.SYNOPSIS
    Batch technician front-end for Northwell system-wide printer mapping.

.DESCRIPTION
    Reads mapping\NorthwellPrinterBatch.csv. Each CSV row is one mapping group:
      ComputerName - one or more target hostnames separated with semicolons
      PrintServer  - one print-server hostname, or blank for full UNC/AD lookup
      QueueName    - one or more queue names separated with semicolons

    The script performs local shape validation first, then requires Northwell
    network authority before any AD/DNS-backed queue resolution. Before live
    mutation it displays the complete resolved plan and requires an explicit MAP
    confirmation unless -ConfirmBatch was supplied by an advanced operator.

    Only groups that return authoritative machine-wide registration proof are
    recorded into the per-user interaction cache. Cache failure never changes the
    batch result and cached values are suggestions only on later interactive runs.
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
$cacheScope = 'northwell'
$cacheAvailable = $false
$cacheModule = Join-Path $repoRoot 'scripts\SasInteractionCache.psm1'
if (Test-Path -LiteralPath $cacheModule -PathType Leaf) {
    try {
        Import-Module $cacheModule -Force -ErrorAction Stop
        $cacheAvailable = $true
    }
    catch {
        $cacheAvailable = $false
    }
}

function Save-SasBatchInteractionHistory {
    param([Parameter(Mandatory)]$Group)

    if (-not $cacheAvailable -or $WhatIf) { return }
    try {
        foreach ($computer in @($Group.Computers | Select-Object -Unique)) {
            $null = Add-SasInteractionCacheEntry -Scope $cacheScope -Kind Host -Value ([string]$computer) -ErrorAction Stop
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$Group.PrintServer)) {
            $null = Add-SasInteractionCacheEntry -Scope $cacheScope -Kind Server -Value ([string]$Group.PrintServer) -ErrorAction Stop
        }
        foreach ($printerValue in @($Group.Printers | Select-Object -Unique)) {
            $printerText = ([string]$printerValue).Trim()
            $null = Add-SasInteractionCacheEntry -Scope $cacheScope -Kind Printer -Value $printerText -ErrorAction Stop
            if ($printerText -match '^\\\\([^\\]+)\\[^\\]+$') {
                $null = Add-SasInteractionCacheEntry -Scope $cacheScope -Kind Server -Value $Matches[1] -ErrorAction Stop
            }
        }
    }
    catch {
        # Interaction history is advisory and must never alter authoritative batch success/failure.
    }
}

if ([string]::IsNullOrWhiteSpace($BatchFile)) {
    $BatchFile = Join-Path $PSScriptRoot 'NorthwellPrinterBatch.csv'
}
$BatchFile = [System.IO.Path]::GetFullPath($BatchFile)
$exampleFile = Join-Path $PSScriptRoot 'Examples\NorthwellPrinterBatch.example.csv'
$latestPath = Join-Path (Join-Path $PSScriptRoot 'Logs') 'LATEST-PATH.txt'

if (-not (Test-Path -LiteralPath $BatchFile -PathType Leaf)) {
    if (-not (Test-Path -LiteralPath $exampleFile -PathType Leaf)) {
        throw "Batch file is missing and the tracked example could not be found: $exampleFile"
    }
    Copy-Item -LiteralPath $exampleFile -Destination $BatchFile -Force
    Write-Host ''
    Write-Host 'A local batch file was created from the tracked synthetic example:' -ForegroundColor Yellow
    Write-Host "  $BatchFile" -ForegroundColor Cyan
    Write-Host 'Replace every REPLACE-WITH-* value, save the file, then run the batch CMD again.' -ForegroundColor Yellow
    Start-Process -FilePath 'notepad.exe' -ArgumentList @($BatchFile) | Out-Null
    exit 2
}

$modulePath = Join-Path $PSScriptRoot 'Modules\NorthwellPrinterMapping.Core.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "Northwell printer core module not found: $modulePath" }
Import-Module $modulePath -Force -ErrorAction Stop

$rows = @(Import-Csv -LiteralPath $BatchFile)
# Local-only first pass: required columns, list splitting, and placeholder rejection.
$null = @(ConvertTo-SasNorthwellPrinterBatchGroups -Rows $rows -ShapeOnly)

# Full resolution may perform AD/DNS activity, so network authority must precede it.
$guardModule = Join-Path $repoRoot 'scripts\SasNetworkGuard.psm1'
if (-not (Test-Path -LiteralPath $guardModule -PathType Leaf)) { throw "Shared Northwell network guard not found: $guardModule" }
Import-Module $guardModule -Force -ErrorAction Stop
Assert-SasNorthwellWifi
Write-Host 'Approved Northwell network posture detected.' -ForegroundColor Green

$groups = @(ConvertTo-SasNorthwellPrinterBatchGroups -Rows $rows)
if ($groups.Count -eq 0) { throw 'Batch plan contains no mapping groups.' }

$engine = Join-Path $PSScriptRoot 'Invoke-NorthwellPrinterMapping.ps1'
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw "Canonical printer engine not found: $engine" }

$runToken = New-SasNorthwellPrinterRunToken
$sessionRoot = Join-Path (Join-Path $PSScriptRoot 'Logs') "NorthwellPrinterBatch-$runToken"
New-Item -ItemType Directory -Path $sessionRoot -Force | Out-Null
$planPath = Join-Path $sessionRoot 'BatchPlan.json'
$summaryPath = Join-Path $sessionRoot 'Summary.json'
$results = New-Object System.Collections.Generic.List[object]

[ordered]@{
    SchemaVersion = 'sas-northwell-printer-batch/v1'
    RunToken = $runToken
    BatchFileName = [System.IO.Path]::GetFileName($BatchFile)
    WhatIf = [bool]$WhatIf
    GroupCount = $groups.Count
    Groups = $groups
    Created = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding UTF8

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' NORTHWELL PRINTER BATCH PLAN' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Batch file: $BatchFile"
Write-Host "Groups    : $($groups.Count)"
foreach ($group in $groups) {
    Write-Host ("Row {0}: {1} -> {2}" -f $group.RowNumber, ($group.Computers -join ', '), ($group.Printers -join ', '))
}
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Plan artifact: $planPath" -ForegroundColor DarkGray
Write-Host ''

if (-not $WhatIf -and -not $ConfirmBatch) {
    $confirmation = Read-Host 'Type MAP to execute this exact batch plan'
    if ($confirmation -cne 'MAP') {
        Write-Host 'CANCELLED: no printer mapping was performed.' -ForegroundColor Yellow
        exit 3
    }
}

$groupIndex = 0
foreach ($group in $groups) {
    $groupIndex++
    $groupRoot = Join-Path $sessionRoot ('Group-{0:D3}' -f $groupIndex)
    $invoke = @{
        ComputerName = @($group.Computers)
        Printer = @($group.Printers)
        SessionRoot = $groupRoot
    }
    if ($WhatIf) { $invoke.WhatIf = $true }

    $success = $false
    $message = ''
    try {
        Write-Host ("Running batch group {0}/{1}..." -f $groupIndex, $groups.Count) -ForegroundColor Cyan
        & $engine @invoke
        if ($WhatIf) {
            $success = $true
            $message = 'PLAN_ONLY'
        }
        else {
            $childSummaryPath = Join-Path $groupRoot 'Summary.json'
            if (-not (Test-Path -LiteralPath $childSummaryPath -PathType Leaf)) {
                throw "Canonical engine did not produce Summary.json for batch group $groupIndex."
            }
            $childSummary = Get-Content -LiteralPath $childSummaryPath -Raw | ConvertFrom-Json
            $success = [bool]$childSummary.Success
            $message = if ($success) { 'MACHINE_WIDE_REGISTRATION_PROVED' } else { 'ENGINE_SUMMARY_FAILED' }
            if ($success) { Save-SasBatchInteractionHistory -Group $group }
        }
    }
    catch {
        $success = $false
        $message = $_.Exception.Message
        Write-Host "Batch group $groupIndex failed: $message" -ForegroundColor Red
    }

    $results.Add([pscustomobject][ordered]@{
        Group = $groupIndex
        SourceRow = $group.RowNumber
        Computers = @($group.Computers)
        Printers = @($group.Printers)
        Success = $success
        Message = $message
        Evidence = $groupRoot
    })
}

$failed = @($results | Where-Object { -not $_.Success })
$summary = [ordered]@{
    SchemaVersion = 'sas-northwell-printer-batch/v1'
    RunToken = $runToken
    Success = ($failed.Count -eq 0)
    Mode = 'NorthwellPrinterBatch'
    ProofLevel = if ($WhatIf) { 'PLAN_ONLY' } else { 'MACHINE_WIDE_REGISTRATION' }
    RuntimePrintObservedByEngine = $false
    TestPagesPrinted = $false
    BatchFileName = [System.IO.Path]::GetFileName($BatchFile)
    TotalGroups = $groups.Count
    CompletedGroups = $results.Count
    FailedGroups = $failed.Count
    Results = $results.ToArray()
    BatchPlan = $planPath
    SessionRoot = $sessionRoot
    Updated = (Get-Date).ToString('o')
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$sessionRoot | Set-Content -LiteralPath $latestPath -Encoding UTF8

Write-Host ''
if ($summary.Success) {
    if ($WhatIf) { Write-Host 'PASS: batch plan resolved. No remote mapping was performed.' -ForegroundColor Green }
    else { Write-Host 'PASS: every batch group returned machine-wide registration proof.' -ForegroundColor Green }
}
else {
    Write-Host "FAIL: $($failed.Count) batch group(s) failed. Evidence was preserved." -ForegroundColor Red
}
Write-Host "Evidence: $sessionRoot" -ForegroundColor Cyan

if (-not $summary.Success) { throw "Northwell printer batch failed in $($failed.Count) group(s). Review $summaryPath" }
