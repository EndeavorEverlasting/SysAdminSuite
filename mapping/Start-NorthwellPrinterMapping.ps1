<#
.SYNOPSIS
    Low-noise technician front-end for Northwell system-wide printer mapping.

.DESCRIPTION
    Collects only the inputs needed for mapping, delegates the actual mutation to
    Invoke-NorthwellPrinterMapping.ps1, suppresses lower-level controller chatter,
    and reports the authoritative SYSTEM + HKLM result.

    If the engine raises a lower-level controller/task error but its new run-scoped
    Status.json proves the requested machine-wide state, that proof wins and the
    technician sees PASS rather than a false failure. Stale evidence from an older
    run can never rescue a fresh failure.
#>

[CmdletBinding()]
param(
    [string[]]$ComputerName,
    [string[]]$Printer,
    [string]$PrintServer,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repoRoot = Split-Path -Parent $PSScriptRoot
$localDefaultsPath = Join-Path $repoRoot 'Config\northwell-printer-defaults.local.json'
$latestPointer = Join-Path $PSScriptRoot 'Logs\LATEST-PATH.txt'

function Split-SasFieldList {
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$Label
    )
    $items = @(
        $Value -split '\s*[,;\r\n]+\s*' |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($items.Count -eq 0) { throw "$Label cannot be blank." }
    return $items
}

function Get-SasNorthwellPrinterLocalDefaults {
    if (-not (Test-Path -LiteralPath $localDefaultsPath -PathType Leaf)) { return $null }
    try {
        $data = Get-Content -LiteralPath $localDefaultsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Local Northwell printer defaults are malformed: $localDefaultsPath. $($_.Exception.Message)"
    }

    $server = [string]$data.PrintServer
    $queue = [string]$data.QueueName
    if ([string]::IsNullOrWhiteSpace($server) -or [string]::IsNullOrWhiteSpace($queue)) {
        throw "Local Northwell printer defaults must contain nonblank PrintServer and QueueName values: $localDefaultsPath"
    }
    if ($server -match '(?i)REPLACE-WITH|EXAMPLE' -or $queue -match '(?i)REPLACE-WITH|EXAMPLE') { return $null }

    return [pscustomobject]@{
        PrintServer = $server.Trim()
        QueueName = $queue.Trim()
    }
}

function Read-SasNorthwellPrinterSets {
    param(
        [AllowNull()][string]$InitialPrintServer,
        [AllowNull()]$LocalDefaults
    )

    $collected = New-Object System.Collections.Generic.List[string]
    $firstSet = $true
    do {
        $serverDefault = ''
        $queueDefault = ''
        if ($firstSet -and -not [string]::IsNullOrWhiteSpace($InitialPrintServer)) {
            $serverDefault = $InitialPrintServer.Trim()
            if ($null -ne $LocalDefaults -and $serverDefault.Equals([string]$LocalDefaults.PrintServer, [System.StringComparison]::OrdinalIgnoreCase)) {
                $queueDefault = [string]$LocalDefaults.QueueName
            }
        }
        elseif ($firstSet -and $null -ne $LocalDefaults) {
            $serverDefault = [string]$LocalDefaults.PrintServer
            $queueDefault = [string]$LocalDefaults.QueueName
        }

        $serverPrompt = if ([string]::IsNullOrWhiteSpace($serverDefault)) { 'Print server hostname (or AD)' } else { "Print server hostname [$serverDefault]" }
        $rawServer = Read-Host $serverPrompt
        if ([string]::IsNullOrWhiteSpace($rawServer)) {
            if ([string]::IsNullOrWhiteSpace($serverDefault)) { throw 'Print server cannot be blank. Enter a hostname or type AD.' }
            $server = $serverDefault
        }
        elseif ($rawServer.Trim().Equals('AD', [System.StringComparison]::OrdinalIgnoreCase)) {
            $server = ''
        }
        else {
            $server = $rawServer.Trim()
        }

        $queuePrompt = if ([string]::IsNullOrWhiteSpace($queueDefault)) { 'Queue name(s), comma-separated' } else { "Queue name(s), comma-separated [$queueDefault]" }
        $rawQueues = Read-Host $queuePrompt
        if ([string]::IsNullOrWhiteSpace($rawQueues)) {
            if ([string]::IsNullOrWhiteSpace($queueDefault)) { throw 'Printer queue cannot be blank.' }
            $rawQueues = $queueDefault
        }

        foreach ($queue in @(Split-SasFieldList -Value $rawQueues -Label 'Printer queue')) {
            if ($queue.StartsWith('\\') -or $queue.StartsWith('//') -or [string]::IsNullOrWhiteSpace($server)) {
                $collected.Add($queue)
            }
            else {
                $collected.Add(('\\{0}\{1}' -f $server, $queue))
            }
        }

        $firstSet = $false
        $more = Read-Host 'Add another server/queue set? [y/N]'
    } while ($more -match '^(?i:y|yes)$')

    return $collected.ToArray()
}

function Get-SasLatestPrinterEvidenceRoot {
    if (-not (Test-Path -LiteralPath $latestPointer -PathType Leaf)) { return $null }
    $value = [string](Get-Content -LiteralPath $latestPointer -Raw -ErrorAction SilentlyContinue)
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    $value = $value.Trim()
    if (-not (Test-Path -LiteralPath $value -PathType Container)) { return $null }
    return $value
}

function Test-SasLatestAuthoritativePrinterProof {
    param([AllowNull()][string]$EvidenceRoot)

    if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) { return $false }
    $summaryPath = Join-Path $EvidenceRoot 'Summary.json'
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { return $false }

    try {
        $summary = Get-Content -LiteralPath $summaryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $expected = [int]$summary.TotalTargets
        if ($expected -lt 1) { return $false }

        $statuses = @(Get-ChildItem -LiteralPath $EvidenceRoot -Filter 'Status.json' -File -Recurse -ErrorAction Stop)
        if ($statuses.Count -ne $expected) { return $false }

        foreach ($statusFile in $statuses) {
            $status = Get-Content -LiteralPath $statusFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not [bool]$status.Success) { return $false }
            if ([string]$status.Identity -notmatch 'SYSTEM$') { return $false }
            if (@($status.Missing).Count -gt 0) { return $false }

            $verified = @($status.MachineWideUNC | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
            foreach ($requested in @($status.Requested)) {
                if ($verified -notcontains ([string]$requested).Trim().ToLowerInvariant()) { return $false }
            }
        }
        return $true
    }
    catch {
        return $false
    }
}

function Write-SasPrinterResult {
    param(
        [Parameter(Mandatory)][bool]$Success,
        [AllowNull()][string]$EvidenceRoot,
        [switch]$RecoveredFromLowerLevelError
    )

    Write-Host ''
    if ($Success) {
        Write-Host 'PASS: requested printer mapping is proven SYSTEM-wide in HKLM.' -ForegroundColor Green
        if ($RecoveredFromLowerLevelError) {
            Write-Host 'A lower-level controller/task error was superseded by authoritative final printer-state proof.' -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host 'FAIL: authoritative machine-wide printer proof was not obtained.' -ForegroundColor Red
    }
    if (-not [string]::IsNullOrWhiteSpace($EvidenceRoot)) {
        Write-Host ("Evidence: {0}" -f $EvidenceRoot) -ForegroundColor DarkGray
    }
}

if (-not $ComputerName -or $ComputerName.Count -eq 0) {
    Write-Host 'Northwell system-wide printer mapping' -ForegroundColor Cyan
    $rawComputers = Read-Host 'Target PC hostname(s)'
    $ComputerName = @(Split-SasFieldList -Value $rawComputers -Label 'Target PC hostname')
}

if (-not $Printer -or $Printer.Count -eq 0) {
    $localDefaults = Get-SasNorthwellPrinterLocalDefaults
    $Printer = @(Read-SasNorthwellPrinterSets -InitialPrintServer $PrintServer -LocalDefaults $localDefaults)
    $PrintServer = $null
}

$guardModule = Join-Path $repoRoot 'scripts\SasNetworkGuard.psm1'
if (-not (Test-Path -LiteralPath $guardModule -PathType Leaf)) { throw "Shared Northwell network guard not found: $guardModule" }
if (-not $WhatIf) {
    Import-Module $guardModule -Force -ErrorAction Stop
    $null = Assert-SasNorthwellWifi
}

$engine = Join-Path $PSScriptRoot 'Invoke-NorthwellPrinterMapping.ps1'
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw "Canonical printer engine not found: $engine" }

$invokeParameters = @{
    ComputerName = $ComputerName
    Printer = $Printer
}
if (-not [string]::IsNullOrWhiteSpace($PrintServer)) { $invokeParameters.PrintServer = $PrintServer }
if ($WhatIf) { $invokeParameters.WhatIf = $true }

Write-Host ('Mapping {0} queue(s) on {1} target(s). No ping sweep. No test page.' -f @($Printer).Count, @($ComputerName).Count) -ForegroundColor Cyan

$previousEvidenceRoot = Get-SasLatestPrinterEvidenceRoot
$engineError = $null
try {
    $null = @(& $engine @invokeParameters *>&1)
}
catch {
    $engineError = $_
}

$evidenceRoot = Get-SasLatestPrinterEvidenceRoot
$freshEvidence = -not [string]::IsNullOrWhiteSpace($evidenceRoot) -and
    ([string]::IsNullOrWhiteSpace($previousEvidenceRoot) -or -not $evidenceRoot.Equals($previousEvidenceRoot, [System.StringComparison]::OrdinalIgnoreCase))
$authoritativeSuccess = $freshEvidence -and (Test-SasLatestAuthoritativePrinterProof -EvidenceRoot $evidenceRoot)

if ($authoritativeSuccess) {
    Write-SasPrinterResult -Success $true -EvidenceRoot $evidenceRoot -RecoveredFromLowerLevelError:($null -ne $engineError)
    return
}

Write-SasPrinterResult -Success $false -EvidenceRoot $(if ($freshEvidence) { $evidenceRoot } else { $null })
if ($null -ne $engineError) {
    throw 'Printer mapping did not produce fresh authoritative HKLM proof. Review the current run evidence if one was created.'
}
throw 'Printer mapping returned without fresh authoritative HKLM proof.'
