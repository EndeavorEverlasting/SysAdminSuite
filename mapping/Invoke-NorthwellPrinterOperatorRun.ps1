#Requires -Version 5.1
<#
.SYNOPSIS
    Operator-facing Northwell printer run wrapper with a local per-user trail.

.DESCRIPTION
    Preserves the existing resilient machine-wide mapper and active-user finalizer.
    This wrapper adds only operator experience: a bounded JSONL event trail and latest
    result under the invoking user's LOCALAPPDATA on the invoking admin box, plus
    explicit MAPPED NOW / ALREADY MAPPED / NOT FOUND / FAILED outcomes.

    Durable operator history is never copied to a target. Existing target-side staging
    remains transient and is cleaned by the owning transport. Sharing the local trail is
    always an operator decision.
#>

[CmdletBinding()]
param([ValidateSet('Map','Unmap')][string]$Action = 'Map')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repoRoot = Split-Path -Parent $PSScriptRoot
$mapper = Join-Path $PSScriptRoot 'Invoke-NorthwellPrinterResilientQuick.ps1'
$finalizer = Join-Path $PSScriptRoot 'Confirm-NorthwellPrinterActiveUserMaterializationResilient.ps1'
$journalModule = Join-Path $repoRoot 'scripts\SasPrinterRunJournal.psm1'
$logsRoot = Join-Path $PSScriptRoot 'Logs'
$latestEvidencePointer = Join-Path $logsRoot 'LATEST-PATH.txt'
foreach ($required in @($mapper,$journalModule)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required printer operator dependency not found: $required" }
}
if ($Action -eq 'Map' -and -not (Test-Path -LiteralPath $finalizer -PathType Leaf)) {
    throw "Required active-user printer finalizer not found: $finalizer"
}
Import-Module $journalModule -Force -ErrorAction Stop

$sessionId = 'printer-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'),([guid]::NewGuid().ToString('N').Substring(0,12))
$startedUtc = [datetime]::UtcNow
$journalWrite = Write-SasPrinterRunJournalEvent -SessionId $sessionId -Event 'RUN_STARTED' -Outcome 'IN_PROGRESS' -Message "Northwell printer $Action started on the local admin box."

function Resolve-SasFreshLocalPrinterEvidenceRoot {
    if (-not (Test-Path -LiteralPath $latestEvidencePointer -PathType Leaf)) { return $null }
    try {
        $saved = [string](Get-Content -LiteralPath $latestEvidencePointer -Raw -ErrorAction Stop)
        if ([string]::IsNullOrWhiteSpace($saved)) { return $null }
        $candidate = [IO.Path]::GetFullPath($saved.Trim())
        $allowedRoot = ([IO.Path]::GetFullPath($logsRoot)).TrimEnd('\')
        if (-not $candidate.StartsWith($allowedRoot + '\',[System.StringComparison]::OrdinalIgnoreCase)) { return $null }
        $summaryPath = Join-Path $candidate 'Summary.json'
        if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { return $null }
        $summaryItem = Get-Item -LiteralPath $summaryPath -ErrorAction Stop
        if ($summaryItem.LastWriteTimeUtc -lt $startedUtc.AddSeconds(-5)) { return $null }
        return $candidate
    }
    catch { return $null }
}

function Read-SasLocalPrinterSummary {
    param([AllowNull()][string]$EvidenceRoot)
    if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) { return $null }
    try { return Get-Content -LiteralPath (Join-Path $EvidenceRoot 'Summary.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { return $null }
}

function Write-SasLocalTrailLocation {
    param([AllowNull()]$JournalResult)
    if ($null -eq $JournalResult) {
        Write-Warning 'The printer result was authoritative, but the optional local operator cache could not be written.'
        return
    }
    Write-Host ("Local admin trail: {0}" -f $JournalResult.JournalPath) -ForegroundColor DarkGray
    Write-Host ("Latest local result: {0}" -f $JournalResult.LatestPath) -ForegroundColor DarkGray
    Write-Host 'Sharing this local trail is optional and remains the admin''s decision.' -ForegroundColor DarkGray
}

$mapperError = $null
try {
    & $mapper -Action $Action
}
catch { $mapperError = $_ }

$evidenceRoot = Resolve-SasFreshLocalPrinterEvidenceRoot
$summary = Read-SasLocalPrinterSummary -EvidenceRoot $evidenceRoot

if ($null -ne $mapperError) {
    $friendly = Get-SasPrinterFriendlyFailure -Message $mapperError.Exception.Message
    $journalWrite = Write-SasPrinterRunJournalEvent -SessionId $sessionId -Event 'MACHINE_WIDE_FAILED' -Outcome $friendly.Outcome -Message $friendly.Headline -EvidenceRoot $evidenceRoot -Summary $summary
    Write-Host ''
    $failureColor = if ($friendly.Outcome -in @('NOT_FOUND','INVALID_PRINTER')) { 'Yellow' } else { 'Red' }
    Write-Host $friendly.Headline -ForegroundColor $failureColor
    Write-SasLocalTrailLocation -JournalResult $journalWrite
    exit 1
}

if ($null -eq $summary -or -not [bool]$summary.Success) {
    $message = 'FAILED: the mapper returned without a complete local Summary.json success proof.'
    $journalWrite = Write-SasPrinterRunJournalEvent -SessionId $sessionId -Event 'MACHINE_WIDE_FAILED' -Outcome 'FAILED' -Message $message -EvidenceRoot $evidenceRoot -Summary $summary
    Write-Host ''
    Write-Host $message -ForegroundColor Red
    Write-SasLocalTrailLocation -JournalResult $journalWrite
    exit 1
}

$machineOutcome = Get-SasPrinterMachineWideOutcome -Summary $summary -Action $Action
$scopeText = '{0} -> {1}' -f (@($summary.Computers) -join ', '),(@($summary.Printers) -join ', ')
switch ($machineOutcome) {
    'MAPPED_NOW' { $machineMessage = "MAPPED NOW: $scopeText. Machine-wide HKLM registration changed and is proven." }
    'ALREADY_MAPPED' { $machineMessage = "ALREADY MAPPED: $scopeText. No machine-wide change was needed; HKLM registration is proven." }
    'MACHINE_WIDE_READY' { $machineMessage = "MACHINE-WIDE READY: $scopeText. HKLM registration is proven." }
    'UNMAPPED_NOW' { $machineMessage = "UNMAPPED NOW: $scopeText. Machine-wide HKLM registration was removed and is proven absent." }
    'ALREADY_UNMAPPED' { $machineMessage = "ALREADY UNMAPPED: $scopeText. No machine-wide change was needed." }
    default { $machineMessage = "MACHINE-WIDE READY: $scopeText." }
}
$journalWrite = Write-SasPrinterRunJournalEvent -SessionId $sessionId -Event 'MACHINE_WIDE_PROVEN' -Outcome $machineOutcome -Message $machineMessage -EvidenceRoot $evidenceRoot -Summary $summary
Write-Host ''
Write-Host $machineMessage -ForegroundColor Green

if ($Action -eq 'Map') {
    $finalizerError = $null
    $powerShell51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    try {
        if (-not (Test-Path -LiteralPath $powerShell51 -PathType Leaf)) { throw "Windows PowerShell 5.1 was not found: $powerShell51" }
        & $powerShell51 -NoLogo -NoProfile -ExecutionPolicy Bypass -File $finalizer -EvidenceRoot $evidenceRoot
        $finalizerExitCode = [int]$LASTEXITCODE
        if ($finalizerExitCode -ne 0) { throw "Active-user finalizer exited with code $finalizerExitCode." }
    }
    catch { $finalizerError = $_ }

    if ($null -ne $finalizerError) {
        $message = "MACHINE-WIDE READY, ACTIVE USER NOT READY: $($finalizerError.Exception.Message)"
        $journalWrite = Write-SasPrinterRunJournalEvent -SessionId $sessionId -Event 'ACTIVE_USER_FAILED' -Outcome 'ACTIVE_USER_FAILED' -Message $message -EvidenceRoot $evidenceRoot -Summary $summary
        Write-Host ''
        Write-Host $message -ForegroundColor Red
        Write-SasLocalTrailLocation -JournalResult $journalWrite
        exit 1
    }

    $activePath = if ([string]::IsNullOrWhiteSpace($evidenceRoot)) { $null } else { Join-Path $evidenceRoot 'ActiveUserMaterialization.json' }
    $active = $null
    if ($null -ne $activePath -and (Test-Path -LiteralPath $activePath -PathType Leaf)) {
        try { $active = Get-Content -LiteralPath $activePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
        catch { $active = $null }
    }
    $pendingNextLogon = $false
    if ($null -ne $active) {
        if ($null -ne $active.PSObject.Properties['PendingNextLogonTargets']) {
            $pendingNextLogon = ([int]$active.PendingNextLogonTargets -gt 0)
        }
        elseif ($null -ne $active.PSObject.Properties['Results']) {
            $pendingNextLogon = (@($active.Results | Where-Object { $_.Success -and $_.PendingNextLogon }).Count -gt 0)
        }
    }
    if ($pendingNextLogon) {
        $finalOutcome = 'READY_NEXT_LOGON'
        $finalMessage = "RESULT: READY NEXT LOGON ($machineOutcome). Machine-wide registration is proven; no active user session required immediate materialization."
    }
    else {
        $finalOutcome = 'READY'
        $finalMessage = "RESULT: READY ($machineOutcome). Machine-wide registration and active-user readiness are proven."
    }
    $journalWrite = Write-SasPrinterRunJournalEvent -SessionId $sessionId -Event 'RUN_COMPLETED' -Outcome $finalOutcome -Message $finalMessage -EvidenceRoot $evidenceRoot -Summary $summary
    Write-Host ''
    Write-Host $finalMessage -ForegroundColor Green
    Write-SasLocalTrailLocation -JournalResult $journalWrite
    exit 0
}

$finalMessage = "RESULT: READY ($machineOutcome). Machine-wide absence is proven."
$journalWrite = Write-SasPrinterRunJournalEvent -SessionId $sessionId -Event 'RUN_COMPLETED' -Outcome 'READY' -Message $finalMessage -EvidenceRoot $evidenceRoot -Summary $summary
Write-Host ''
Write-Host $finalMessage -ForegroundColor Green
Write-SasLocalTrailLocation -JournalResult $journalWrite
exit 0
