#Requires -Version 5.1
<#
.SYNOPSIS
    Resilient quick front-end for canonical Northwell printer mapping.

.DESCRIPTION
    Runs Start-NorthwellPrinterMapping.ps1 unchanged. If that canonical path fails,
    this wrapper considers the shareless Task Scheduler + Remote Registry fallback
    only when fresh operation-scoped evidence proves every target failed during
    administrative-share staging before any Status.json or changed-printer evidence
    existed. Partial batches, ambiguous evidence, task failures, and post-mutation
    failures are never replayed automatically.
#>

[CmdletBinding()]
param(
    [ValidateSet('Map','Unmap')][string]$Action = 'Map',
    [string[]]$ComputerName,
    [string[]]$Printer,
    [string]$PrintServer,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$startScript = Join-Path $PSScriptRoot 'Start-NorthwellPrinterMapping.ps1'
$fallbackScript = Join-Path $PSScriptRoot 'Invoke-NorthwellPrinterTaskRegistryFallback.ps1'
$logsRoot = Join-Path $PSScriptRoot 'Logs'
if (-not (Test-Path -LiteralPath $startScript -PathType Leaf)) { throw "Canonical printer front-end not found: $startScript" }
if (-not (Test-Path -LiteralPath $fallbackScript -PathType Leaf)) { throw "Shareless printer fallback not found: $fallbackScript" }

function Test-SasAdministrativeStagingFailureBeforeMutation {
    param([Parameter(Mandatory)][string]$EvidenceRoot)
    $summaryPath = Join-Path $EvidenceRoot 'Summary.json'
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { return $false }
    if (@(Get-ChildItem -LiteralPath $EvidenceRoot -Filter 'Status.json' -File -Recurse -ErrorAction SilentlyContinue).Count -ne 0) { return $false }

    try { $summary = Get-Content -LiteralPath $summaryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { return $false }
    if ([bool]$summary.Success) { return $false }
    $total = [int]$summary.TotalTargets
    $results = @($summary.Results)
    if ($total -lt 1 -or $results.Count -ne $total -or [int]$summary.CompletedTargets -ne $total) { return $false }

    foreach ($result in $results) {
        if ([bool]$result.Success) { return $false }
        if ([string]$result.Stage -ne 'Failed') { return $false }
        $message = [string]$result.Message
        if ($message -notmatch '(?i)^Admin share unavailable(?:\s|:|\b)') { return $false }
        $changedProperty = $result.PSObject.Properties['ChangedPrinters']
        if ($null -ne $changedProperty -and @($changedProperty.Value).Count -ne 0) { return $false }
        $stagingProperty = $result.PSObject.Properties['StagingShare']
        if ($null -ne $stagingProperty -and -not [string]::IsNullOrWhiteSpace([string]$stagingProperty.Value)) { return $false }
    }
    return $true
}

function Resolve-SasFreshOperationEvidenceRoot {
    param(
        [Parameter(Mandatory)][datetime]$StartedUtc,
        [Parameter(Mandatory)][ValidateSet('Map','Unmap')][string]$Operation
    )
    if (-not (Test-Path -LiteralPath $logsRoot -PathType Container)) { return $null }
    $prefix = if ($Operation -eq 'Map') { 'NorthwellPrinterMap-' } else { 'NorthwellPrinterUnmap-' }
    $candidates = @(
        Get-ChildItem -LiteralPath $logsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name.StartsWith($prefix,[System.StringComparison]::OrdinalIgnoreCase) } |
            ForEach-Object {
                $summary = Join-Path $_.FullName 'Summary.json'
                if (Test-Path -LiteralPath $summary -PathType Leaf) {
                    $item = Get-Item -LiteralPath $summary -ErrorAction SilentlyContinue
                    if ($null -ne $item -and $item.LastWriteTimeUtc -ge $StartedUtc.AddSeconds(-2)) { $_ }
                }
            }
    )
    if ($candidates.Count -ne 1) { return $null }
    return $candidates[0].FullName
}

$startedUtc = (Get-Date).ToUniversalTime()
$invoke = @{ Action=$Action }
if ($ComputerName) { $invoke.ComputerName = $ComputerName }
if ($Printer) { $invoke.Printer = $Printer }
if (-not [string]::IsNullOrWhiteSpace($PrintServer)) { $invoke.PrintServer = $PrintServer }
if ($WhatIf) { $invoke.WhatIf = $true }

$primaryError = $null
try {
    & $startScript @invoke
    return
}
catch { $primaryError = $_ }

if ($WhatIf) { throw $primaryError.Exception.Message }

$evidenceRoot = Resolve-SasFreshOperationEvidenceRoot -StartedUtc $startedUtc -Operation $Action
if ([string]::IsNullOrWhiteSpace($evidenceRoot)) {
    throw "Canonical printer mapping failed and exactly one fresh operation-scoped evidence root could not be resolved. Shareless replay was refused. Original error: $($primaryError.Exception.Message)"
}
if (-not (Test-SasAdministrativeStagingFailureBeforeMutation -EvidenceRoot $evidenceRoot)) {
    throw "Canonical printer mapping failed outside the proven pre-mutation administrative-staging boundary. Shareless replay was refused. Evidence: $evidenceRoot. Original error: $($primaryError.Exception.Message)"
}

$summaryPath = Join-Path $evidenceRoot 'Summary.json'
$planPath = Join-Path $evidenceRoot 'ResolvedPlan.json'
if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) {
    throw "Administrative staging failed safely, but the resolved operation plan is missing: $planPath"
}

Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $evidenceRoot 'AdministrativeStagingFailure.json') -Force -ErrorAction Stop
Copy-Item -LiteralPath $planPath -Destination (Join-Path $evidenceRoot 'AdministrativeStagingFailure.ResolvedPlan.json') -Force -ErrorAction Stop
$originalUndo = Join-Path $evidenceRoot 'UndoPlan.json'
if (Test-Path -LiteralPath $originalUndo -PathType Leaf) {
    Copy-Item -LiteralPath $originalUndo -Destination (Join-Path $evidenceRoot 'AdministrativeStagingFailure.UndoPlan.json') -Force -ErrorAction Stop
}
$primaryError.Exception.Message | Set-Content -LiteralPath (Join-Path $evidenceRoot 'AdministrativeStagingFailure.txt') -Encoding UTF8

$plan = Get-Content -LiteralPath $planPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$planComputers = @($plan.Computers | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$planPrinters = @($plan.Printers | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$planState = [string]$plan.DesiredState
if ($planComputers.Count -lt 1 -or $planPrinters.Count -lt 1 -or $planState -notin @('Present','Absent')) {
    throw "Resolved printer plan is incomplete or unsafe for shareless replay: $planPath"
}

Write-Host ''
Write-Host 'Administrative SMB staging failed before target mutation.' -ForegroundColor Yellow
Write-Host 'Trying shareless SYSTEM Task Scheduler + Remote Registry HKLM proof.' -ForegroundColor Cyan
Write-Host "Evidence remains in the same operation root: $evidenceRoot" -ForegroundColor DarkGray

$fallbackError = $null
try {
    & $fallbackScript -ComputerName $planComputers -Printer $planPrinters -DesiredState $planState -SessionRoot $evidenceRoot
}
catch { $fallbackError = $_ }

$finalSummary = $null
try { $finalSummary = Get-Content -LiteralPath $summaryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
catch {}
$statusFiles = @(Get-ChildItem -LiteralPath $evidenceRoot -Filter 'Status.json' -File -Recurse -ErrorAction SilentlyContinue)
$finalSuccess = (
    $null -ne $finalSummary -and
    [bool]$finalSummary.Success -and
    [int]$finalSummary.TotalTargets -eq $planComputers.Count -and
    [int]$finalSummary.CompletedTargets -eq $planComputers.Count -and
    $statusFiles.Count -eq $planComputers.Count
)
if ($finalSuccess) {
    foreach ($statusFile in $statusFiles) {
        try { $status = Get-Content -LiteralPath $statusFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
        catch { $finalSuccess = $false; break }
        if (-not [bool]$status.Success -or [string]$status.Identity -notmatch 'SYSTEM$' -or [string]$status.StatusAuthority -ne 'CONTROLLER_REMOTE_REGISTRY') {
            $finalSuccess = $false
            break
        }
    }
}

if ($finalSuccess) {
    Write-Host ''
    Write-Host 'PASS: administrative-share staging was bypassed and authoritative remote HKLM printer proof was obtained.' -ForegroundColor Green
    Write-Host "Evidence: $evidenceRoot" -ForegroundColor DarkGray
    return
}

if ($null -ne $fallbackError) {
    throw "Shareless printer fallback did not obtain authoritative remote HKLM proof. Evidence: $evidenceRoot. Fallback error: $($fallbackError.Exception.Message)"
}
throw "Shareless printer fallback returned without complete authoritative remote HKLM proof. Evidence: $evidenceRoot"
