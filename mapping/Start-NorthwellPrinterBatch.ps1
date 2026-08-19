<#
.SYNOPSIS
    Batch technician front-end for Northwell system-wide printer mapping.

.DESCRIPTION
    Reads mapping\NorthwellPrinterBatch.csv. Each CSV row is one mapping group:
      ComputerName - one or more target hostnames separated with semicolons
      PrintServer  - one print-server hostname, or blank for full UNC/AD lookup
      QueueName    - one or more queue names separated with semicolons

    Example:
      PC001;PC002,SYKPNHPHPS01V,LS001-EMS01;QUEUE02

    Each row delegates to the canonical Invoke-NorthwellPrinterMapping.ps1 engine,
    so SYSTEM identity, PrintUIEntry /ga, HKLM machine-wide proof, cleanup, and
    evidence behavior stay identical to the proven single/interactive path.
#>

[CmdletBinding()]
param(
    [string]$BatchFile,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
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
    Write-Host 'A local batch file was created from the tracked example:' -ForegroundColor Yellow
    Write-Host "  $BatchFile" -ForegroundColor Cyan
    Write-Host 'Replace REPLACE-WITH-PC-HOSTNAME, save the file, then run the batch CMD again.' -ForegroundColor Yellow
    Start-Process -FilePath 'notepad.exe' -ArgumentList @($BatchFile) | Out-Null
    exit 2
}

$modulePath = Join-Path $PSScriptRoot 'Modules\NorthwellPrinterMapping.Core.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "Northwell printer core module not found: $modulePath"
}
Import-Module $modulePath -Force -ErrorAction Stop

$rows = @(Import-Csv -LiteralPath $BatchFile)
$groups = @(ConvertTo-SasNorthwellPrinterBatchGroups -Rows $rows)
if ($groups.Count -eq 0) {
    throw 'Batch plan contains no mapping groups.'
}

$guardModule = Join-Path $repoRoot 'scripts\SasNetworkGuard.psm1'
if (-not (Test-Path -LiteralPath $guardModule -PathType Leaf)) {
    throw "Shared Northwell network guard not found: $guardModule"
}
if (-not $WhatIf) {
    Import-Module $guardModule -Force -ErrorAction Stop
    Assert-SasNorthwellWifi
    Write-Host 'Approved Northwell network posture detected.' -ForegroundColor Green
}

$engine = Join-Path $PSScriptRoot 'Invoke-NorthwellPrinterMapping.ps1'
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) {
    throw "Canonical printer engine not found: $engine"
}

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
Write-Host ''

$groupIndex = 0
foreach ($group in $groups) {
    $groupIndex++
    $groupRoot = Join-Path $sessionRoot ('Group-{0:D3}' -f $groupIndex)
    $invoke = @{
        ComputerName = @($group.Computers)
        Printer = @($group.Printers)
        SessionRoot = $groupRoot
    }
    if ($WhatIf) {
        $invoke.WhatIf = $true
    }

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
    Results = @($results)
    BatchPlan = $planPath
    SessionRoot = $sessionRoot
    Updated = (Get-Date).ToString('o')
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$sessionRoot | Set-Content -LiteralPath $latestPath -Encoding UTF8

Write-Host ''
if ($summary.Success) {
    if ($WhatIf) {
        Write-Host 'PASS: batch plan resolved. No remote mapping was performed.' -ForegroundColor Green
    }
    else {
        Write-Host 'PASS: every batch group returned machine-wide registration proof.' -ForegroundColor Green
    }
}
else {
    Write-Host "FAIL: $($failed.Count) batch group(s) failed. Evidence was preserved." -ForegroundColor Red
}
Write-Host "Evidence: $sessionRoot" -ForegroundColor Cyan

if (-not $summary.Success) {
    throw "Northwell printer batch failed in $($failed.Count) group(s). Review $summaryPath"
}
