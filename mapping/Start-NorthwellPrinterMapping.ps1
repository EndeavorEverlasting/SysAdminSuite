<#
.SYNOPSIS
    Low-noise technician front-end for Northwell system-wide printer mapping.

.DESCRIPTION
    Collects only the inputs needed for mapping, delegates the actual mutation to
    Invoke-NorthwellPrinterMapping.ps1, suppresses lower-level controller chatter,
    and reports the authoritative SYSTEM + HKLM result.

    Successful interactions are remembered in a bounded per-user cache and offered
    only as input suggestions on later runs. Cached values never bypass canonical
    target/queue resolution and never count as printer-state proof. If cache state
    is stale, malformed, locked, or unavailable, mapping continues without it.

    If the engine raises a lower-level controller/task error but its new run-scoped
    Status.json proves the requested machine-wide state, that proof wins and the
    technician sees PASS rather than a false failure. Stale evidence from an older
    run can never rescue a fresh failure. Preview runs remain plan-only and early
    input/DNS failures retain their original actionable message.
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

function Get-SasRecentInteractionValues {
    param(
        [Parameter(Mandatory)][ValidateSet('Host','Printer','Server')][string]$Kind,
        [ValidateRange(1,20)][int]$Top = 10
    )

    if (-not $cacheAvailable) { return @() }
    try {
        return @(
            Get-SasInteractionCacheEntries -Scope $cacheScope -Kind $Kind -Top $Top -ErrorAction Stop |
                ForEach-Object { [string]$_.DisplayValue } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
    }
    catch {
        return @()
    }
}

function Read-SasRecentNumberSelection {
    param(
        [Parameter(Mandatory)][string]$RawValue,
        [Parameter(Mandatory)][string[]]$RecentValues,
        [Parameter(Mandatory)][string]$Label
    )

    $trimmed = $RawValue.Trim()
    if ($trimmed -notmatch '^\d+(?:\s*[,;]\s*\d+)*$') { return $null }
    $selected = New-Object System.Collections.Generic.List[string]
    foreach ($rawIndex in @($trimmed -split '\s*[,;]\s*')) {
        $index = [int]$rawIndex
        if ($index -lt 1 -or $index -gt $RecentValues.Count) {
            throw "$Label recent selection '$index' is outside the displayed range 1-$($RecentValues.Count)."
        }
        $selected.Add($RecentValues[$index - 1])
    }
    return @($selected.ToArray() | Select-Object -Unique)
}

function Show-SasRecentValues {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string[]]$Values
    )

    if ($Values.Count -eq 0) { return }
    Write-Host ''
    Write-Host $Title -ForegroundColor DarkCyan
    for ($index = 0; $index -lt $Values.Count; $index++) {
        Write-Host ('  {0}. {1}' -f ($index + 1), $Values[$index])
    }
}

function Save-SasPrinterInteractionHistory {
    param(
        [Parameter(Mandatory)][string[]]$Computers,
        [Parameter(Mandatory)][string[]]$Printers,
        [AllowNull()][string]$ExplicitPrintServer
    )

    if (-not $cacheAvailable) { return }
    try {
        foreach ($computer in @($Computers | Select-Object -Unique)) {
            $null = Add-SasInteractionCacheEntry -Scope $cacheScope -Kind Host -Value ([string]$computer) -ErrorAction Stop
        }
        if (-not [string]::IsNullOrWhiteSpace($ExplicitPrintServer)) {
            $null = Add-SasInteractionCacheEntry -Scope $cacheScope -Kind Server -Value $ExplicitPrintServer -ErrorAction Stop
        }
        foreach ($printerValue in @($Printers | Select-Object -Unique)) {
            $printerText = ([string]$printerValue).Trim()
            $null = Add-SasInteractionCacheEntry -Scope $cacheScope -Kind Printer -Value $printerText -ErrorAction Stop
            if ($printerText -match '^\\\\([^\\]+)\\[^\\]+$') {
                $null = Add-SasInteractionCacheEntry -Scope $cacheScope -Kind Server -Value $Matches[1] -ErrorAction Stop
            }
        }
    }
    catch {
        # Cache persistence is advisory. Authoritative printer success must not be downgraded by cache failure.
    }
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
    $recentHosts = @(Get-SasRecentInteractionValues -Kind Host -Top 10)
    Show-SasRecentValues -Title 'Recent proven target PCs:' -Values $recentHosts
    $hostPrompt = if ($recentHosts.Count -gt 0) { 'Target PC(s): recent number(s) or hostname(s)' } else { 'Target PC hostname(s)' }
    $rawComputers = Read-Host $hostPrompt
    if ([string]::IsNullOrWhiteSpace($rawComputers)) { throw 'Target PC hostname cannot be blank.' }
    $selectedHosts = if ($recentHosts.Count -gt 0) { Read-SasRecentNumberSelection -RawValue $rawComputers -RecentValues $recentHosts -Label 'Target PC' } else { $null }
    if ($null -ne $selectedHosts) { $ComputerName = @($selectedHosts) }
    else { $ComputerName = @(Split-SasFieldList -Value $rawComputers -Label 'Target PC hostname') }
}

$explicitPrintServerForCache = $PrintServer
if (-not $Printer -or $Printer.Count -eq 0) {
    $recentPrinters = @(Get-SasRecentInteractionValues -Kind Printer -Top 10)
    $selectedPrinters = $null
    if ($recentPrinters.Count -gt 0) {
        Show-SasRecentValues -Title 'Recent proven printer inputs:' -Values $recentPrinters
        $rawRecentPrinter = Read-Host 'Printer number(s), or Enter to choose server/queue manually'
        if (-not [string]::IsNullOrWhiteSpace($rawRecentPrinter)) {
            $selectedPrinters = Read-SasRecentNumberSelection -RawValue $rawRecentPrinter -RecentValues $recentPrinters -Label 'Printer'
            if ($null -eq $selectedPrinters) {
                throw 'Choose displayed printer number(s), or press Enter for manual server/queue entry.'
            }
        }
    }

    if ($null -ne $selectedPrinters) {
        $Printer = @($selectedPrinters)
        $PrintServer = $null
    }
    else {
        $localDefaults = Get-SasNorthwellPrinterLocalDefaults
        $initialServer = $PrintServer
        if ([string]::IsNullOrWhiteSpace($initialServer) -and $null -eq $localDefaults) {
            $recentServers = @(Get-SasRecentInteractionValues -Kind Server -Top 1)
            if ($recentServers.Count -gt 0) { $initialServer = $recentServers[0] }
        }
        $Printer = @(Read-SasNorthwellPrinterSets -InitialPrintServer $initialServer -LocalDefaults $localDefaults)
        $PrintServer = $null
    }
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

Write-Host ('Mapping {0} queue(s) on {1} target(s). No reachability sweep. No test page.' -f @($Printer).Count, @($ComputerName).Count) -ForegroundColor Cyan

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

if ($WhatIf) {
    if ($null -ne $engineError) { throw $engineError.Exception.Message }
    Write-Host ''
    Write-Host 'PLAN: preview complete; no printer changes were made.' -ForegroundColor Green
    if ($freshEvidence) { Write-Host ("Evidence: {0}" -f $evidenceRoot) -ForegroundColor DarkGray }
    return
}

$authoritativeSuccess = $freshEvidence -and (Test-SasLatestAuthoritativePrinterProof -EvidenceRoot $evidenceRoot)
if ($authoritativeSuccess) {
    Save-SasPrinterInteractionHistory -Computers @($ComputerName) -Printers @($Printer) -ExplicitPrintServer $explicitPrintServerForCache
    Write-SasPrinterResult -Success $true -EvidenceRoot $evidenceRoot -RecoveredFromLowerLevelError:($null -ne $engineError)
    return
}

if ($null -ne $engineError -and -not $freshEvidence) {
    throw $engineError.Exception.Message
}

Write-SasPrinterResult -Success $false -EvidenceRoot $(if ($freshEvidence) { $evidenceRoot } else { $null })
if ($null -ne $engineError) {
    throw 'Printer mapping produced fresh evidence but did not prove the requested SYSTEM-wide HKLM state. Review the evidence path above.'
}
throw 'Printer mapping returned without fresh authoritative HKLM proof.'
