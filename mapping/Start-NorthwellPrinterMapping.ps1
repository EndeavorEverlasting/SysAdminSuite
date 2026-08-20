<#
.SYNOPSIS
    Low-noise technician front-end for reversible Northwell system-wide printer management.

.DESCRIPTION
    Maps or unmaps shared printer queues for one or more PCs using the canonical
    desired-state engine. Recent authoritatively proven hosts/printers/servers are
    offered as numbered input suggestions to reduce technician reconstruction.

    Cache state is advisory only. Every live action still resolves canonical input,
    runs under SYSTEM, and requires fresh HKLM desired-state proof. Cache corruption,
    staleness, lock contention, or write failure never changes printer success.
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

$repoRoot = Split-Path -Parent $PSScriptRoot
$localDefaultsPath = Join-Path $repoRoot 'Config\northwell-printer-defaults.local.json'
$cacheScope = 'northwell'
$cacheAvailable = $false
$cacheModule = Join-Path $repoRoot 'scripts\SasInteractionCache.psm1'
if (Test-Path -LiteralPath $cacheModule -PathType Leaf) {
    try {
        Import-Module $cacheModule -Force -ErrorAction Stop
        $cacheAvailable = $true
    }
    catch { $cacheAvailable = $false }
}

function Split-SasFieldList {
    param([Parameter(Mandatory)][string]$Value,[Parameter(Mandatory)][string]$Label)
    $items = @($Value -split '\s*[,;\r\n]+\s*' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($items.Count -eq 0) { throw "$Label cannot be blank." }
    return $items
}

function Get-SasRecentInteractionValues {
    param([Parameter(Mandatory)][ValidateSet('Host','Printer','Server')][string]$Kind,[ValidateRange(1,20)][int]$Top = 10)
    if (-not $cacheAvailable) { return @() }
    try {
        return @(Get-SasInteractionCacheEntries -Scope $cacheScope -Kind $Kind -Top $Top -ErrorAction Stop |
            ForEach-Object { [string]$_.DisplayValue } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    catch { return @() }
}

function Read-SasRecentNumberSelection {
    param([Parameter(Mandatory)][string]$RawValue,[Parameter(Mandatory)][string[]]$RecentValues,[Parameter(Mandatory)][string]$Label)
    $trimmed = $RawValue.Trim()
    if ($trimmed -notmatch '^\d+(?:\s*[,;]\s*\d+)*$') { return $null }
    $selected = New-Object System.Collections.Generic.List[string]
    foreach ($rawIndex in @($trimmed -split '\s*[,;]\s*')) {
        $index = [int]$rawIndex
        if ($index -lt 1 -or $index -gt $RecentValues.Count) { throw "$Label recent selection '$index' is outside the displayed range 1-$($RecentValues.Count)." }
        $selected.Add($RecentValues[$index - 1])
    }
    return @($selected.ToArray() | Select-Object -Unique)
}

function Show-SasRecentValues {
    param([Parameter(Mandatory)][string]$Title,[Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Values)
    if ($Values.Count -eq 0) { return }
    Write-Host ''
    Write-Host $Title -ForegroundColor DarkCyan
    for ($index = 0; $index -lt $Values.Count; $index++) { Write-Host ('  {0}. {1}' -f ($index + 1),$Values[$index]) }
}

function Save-SasPrinterInteractionHistory {
    param([Parameter(Mandatory)][string[]]$Computers,[Parameter(Mandatory)][string[]]$Printers,[AllowNull()][string]$ExplicitPrintServer)
    if (-not $cacheAvailable) { return }
    try {
        foreach ($computer in @($Computers | Select-Object -Unique)) { $null = Add-SasInteractionCacheEntry -Scope $cacheScope -Kind Host -Value ([string]$computer) -ErrorAction Stop }
        if (-not [string]::IsNullOrWhiteSpace($ExplicitPrintServer)) { $null = Add-SasInteractionCacheEntry -Scope $cacheScope -Kind Server -Value $ExplicitPrintServer -ErrorAction Stop }
        foreach ($printerValue in @($Printers | Select-Object -Unique)) {
            $printerText = ([string]$printerValue).Trim()
            $null = Add-SasInteractionCacheEntry -Scope $cacheScope -Kind Printer -Value $printerText -ErrorAction Stop
            if ($printerText -match '^\\\\([^\\]+)\\[^\\]+$') { $null = Add-SasInteractionCacheEntry -Scope $cacheScope -Kind Server -Value $Matches[1] -ErrorAction Stop }
        }
    }
    catch {
        # Cache persistence is advisory. Authoritative printer success must not be downgraded by cache failure.
    }
}

function Get-SasNorthwellPrinterLocalDefaults {
    if (-not (Test-Path -LiteralPath $localDefaultsPath -PathType Leaf)) { return $null }
    try { $data = Get-Content -LiteralPath $localDefaultsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Local Northwell printer defaults are malformed: $localDefaultsPath. $($_.Exception.Message)" }
    $server = [string]$data.PrintServer
    $queue = [string]$data.QueueName
    if ([string]::IsNullOrWhiteSpace($server) -or [string]::IsNullOrWhiteSpace($queue)) { throw "Local Northwell printer defaults must contain nonblank PrintServer and QueueName values: $localDefaultsPath" }
    if ($server -match '(?i)REPLACE-WITH|EXAMPLE' -or $queue -match '(?i)REPLACE-WITH|EXAMPLE') { return $null }
    return [pscustomobject]@{ PrintServer=$server.Trim(); QueueName=$queue.Trim() }
}

function Read-SasNorthwellPrinterSets {
    param([AllowNull()][string]$InitialPrintServer,[AllowNull()]$LocalDefaults)
    $collected = New-Object System.Collections.Generic.List[string]
    $firstSet = $true
    do {
        $serverDefault = ''
        $queueDefault = ''
        if ($firstSet -and -not [string]::IsNullOrWhiteSpace($InitialPrintServer)) {
            $serverDefault = $InitialPrintServer.Trim()
            if ($null -ne $LocalDefaults -and $serverDefault.Equals([string]$LocalDefaults.PrintServer,[System.StringComparison]::OrdinalIgnoreCase)) { $queueDefault = [string]$LocalDefaults.QueueName }
        }
        elseif ($firstSet -and $null -ne $LocalDefaults) {
            $serverDefault = [string]$LocalDefaults.PrintServer
            $queueDefault = [string]$LocalDefaults.QueueName
        }

        Write-Host ''
        if ($firstSet -and $null -ne $LocalDefaults) { Write-Host 'Operator-local default is configured. Press Enter to accept the bracketed value.' -ForegroundColor Green }
        elseif ($firstSet) { Write-Host 'No operator-local printer default is configured. Use Edit-NorthwellPrinter-Defaults.cmd if you want one.' -ForegroundColor DarkGray }

        $serverPrompt = if ([string]::IsNullOrWhiteSpace($serverDefault)) { 'Print server hostname (or AD)' } else { "Print server hostname [$serverDefault]" }
        $rawServer = Read-Host $serverPrompt
        if ([string]::IsNullOrWhiteSpace($rawServer)) {
            if ([string]::IsNullOrWhiteSpace($serverDefault)) { throw 'Print server cannot be blank. Enter a hostname or type AD.' }
            $server = $serverDefault
        }
        elseif ($rawServer.Trim().Equals('AD',[System.StringComparison]::OrdinalIgnoreCase)) { $server = '' }
        else { $server = $rawServer.Trim() }

        $queuePrompt = if ([string]::IsNullOrWhiteSpace($queueDefault)) { 'Queue name(s), comma-separated' } else { "Queue name(s), comma-separated [$queueDefault]" }
        $rawQueues = Read-Host $queuePrompt
        if ([string]::IsNullOrWhiteSpace($rawQueues)) {
            if ([string]::IsNullOrWhiteSpace($queueDefault)) { throw 'Printer queue cannot be blank.' }
            $rawQueues = $queueDefault
        }
        foreach ($queue in @(Split-SasFieldList -Value $rawQueues -Label 'Printer queue')) {
            if ($queue.StartsWith('\\') -or $queue.StartsWith('//') -or [string]::IsNullOrWhiteSpace($server)) { $collected.Add($queue) }
            else { $collected.Add(('\\{0}\{1}' -f $server,$queue)) }
        }
        $firstSet = $false
        $more = Read-Host 'Add another print server / queue set? [y/N]'
    } while ($more -match '^(?i:y|yes)$')
    return $collected.ToArray()
}

function Test-SasLatestAuthoritativePrinterProof {
    param([AllowNull()][string]$EvidenceRoot,[ValidateSet('Present','Absent')][string]$DesiredState = 'Present')
    if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) { return $false }
    $summaryPath = Join-Path $EvidenceRoot 'Summary.json'
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { return $false }
    try {
        $summary = Get-Content -LiteralPath $summaryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $expected = [int]$summary.TotalTargets
        if ($expected -lt 1) { return $false }
        if (-not [bool]$summary.Success) { return $false }
        if ([int]$summary.CompletedTargets -ne $expected) { return $false }
        if ($null -ne $summary.PSObject.Properties['DesiredState'] -and -not ([string]$summary.DesiredState).Equals($DesiredState,[System.StringComparison]::OrdinalIgnoreCase)) { return $false }
        $statuses = @(Get-ChildItem -LiteralPath $EvidenceRoot -Filter 'Status.json' -File -Recurse -ErrorAction Stop)
        if ($statuses.Count -ne $expected) { return $false }
        foreach ($statusFile in $statuses) {
            $status = Get-Content -LiteralPath $statusFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not [bool]$status.Success) { return $false }
            if ([string]$status.Identity -notmatch 'SYSTEM$') { return $false }
            $verified = @($status.MachineWideUNC | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
            foreach ($requested in @($status.Requested)) {
                $normalized = ([string]$requested).Trim().ToLowerInvariant()
                if ($DesiredState -eq 'Present' -and $verified -notcontains $normalized) { return $false }
                if ($DesiredState -eq 'Absent' -and $verified -contains $normalized) { return $false }
            }
            if ($DesiredState -eq 'Present' -and @($status.Missing).Count -gt 0) { return $false }
            if ($DesiredState -eq 'Absent' -and @($status.StillPresent).Count -gt 0) { return $false }
        }
        return $true
    }
    catch { return $false }
}

function Write-SasPrinterResult {
    param([Parameter(Mandatory)][bool]$Success,[Parameter(Mandatory)][string]$Action,[AllowNull()][string]$EvidenceRoot,[switch]$RecoveredFromLowerLevelError)
    Write-Host ''
    if ($Success) {
        Write-Host ("PASS: requested printer {0} is proven SYSTEM-wide in HKLM." -f $Action.ToLowerInvariant()) -ForegroundColor Green
        if ($RecoveredFromLowerLevelError) { Write-Host 'A lower-level controller/task error was superseded by authoritative final printer-state proof.' -ForegroundColor DarkGray }
    }
    else { Write-Host 'FAIL: authoritative machine-wide printer proof was not obtained.' -ForegroundColor Red }
    if (-not [string]::IsNullOrWhiteSpace($EvidenceRoot)) { Write-Host ("Evidence: {0}" -f $EvidenceRoot) -ForegroundColor DarkGray }
}

function Write-SasPrinterFailureDiagnostic {
    param([AllowNull()][string]$EvidenceRoot)
    if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) { return }
    $diagnostic = Join-Path $PSScriptRoot 'Diagnose-NorthwellPrinterEvidence.ps1'
    if (-not (Test-Path -LiteralPath $diagnostic -PathType Leaf)) {
        Write-Warning "Fresh printer evidence exists but the read-only diagnostic is missing: $diagnostic"
        return
    }
    try {
        & $diagnostic -EvidenceRoot $EvidenceRoot
    }
    catch {
        Write-Warning "Fresh printer evidence could not be summarized automatically: $($_.Exception.Message)"
    }
}

if (-not $ComputerName -or $ComputerName.Count -eq 0) {
    Write-Host "Northwell system-wide printer $Action" -ForegroundColor Cyan
    Write-Host 'This controller may use WAB, hardwire, or authenticated VPN.' -ForegroundColor DarkGray
    $recentHosts = @(Get-SasRecentInteractionValues -Kind Host -Top 10)
    Show-SasRecentValues -Title 'Recent proven target PCs:' -Values $recentHosts
    if ($recentHosts.Count -gt 0) { $rawComputers = Read-Host 'Target PC(s): recent number(s) or hostname(s)' }
    else { $rawComputers = Read-Host 'Target PC hostname(s), comma/semicolon-separated' }
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
            if ($null -eq $selectedPrinters) { throw 'Choose displayed printer number(s), or press Enter for manual server/queue entry.' }
        }
    }
    if ($null -ne $selectedPrinters) {
        $Printer = @($selectedPrinters)
        $PrintServer = $null
    }
    else {
        $localDefaults = Get-SasNorthwellPrinterLocalDefaults
        if (-not [string]::IsNullOrWhiteSpace($PrintServer)) {
            $Printer = @(Read-SasNorthwellPrinterSets -InitialPrintServer $PrintServer -LocalDefaults $localDefaults)
        }
        else {
            $initialServer = $null
            if ($null -eq $localDefaults) {
                $recentServers = @(Get-SasRecentInteractionValues -Kind Server -Top 1)
                if ($recentServers.Count -gt 0) { $initialServer = $recentServers[0] }
            }
            $Printer = @(Read-SasNorthwellPrinterSets -InitialPrintServer $initialServer -LocalDefaults $localDefaults)
        }
        $PrintServer = $null
    }
}

$authorityModule = Join-Path $repoRoot 'scripts\SasNorthwellNetworkAuthority.psm1'
if (-not (Test-Path -LiteralPath $authorityModule -PathType Leaf)) { throw "Northwell network authority module not found: $authorityModule" }
if (-not $WhatIf) {
    Import-Module $authorityModule -Force -ErrorAction Stop
    $authority = Assert-SasNorthwellNetwork
    Write-Host ("Approved Northwell network authority: {0} ({1})" -f $authority.Route,$authority.Evidence) -ForegroundColor Green
}

$engine = Join-Path $PSScriptRoot 'Invoke-NorthwellPrinterState.ps1'
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw "Canonical reversible printer engine not found: $engine" }
$desiredState = if ($Action -eq 'Map') { 'Present' } else { 'Absent' }
$evidencePrefix = if ($Action -eq 'Map') { 'NorthwellPrinterMap' } else { 'NorthwellPrinterUnmap' }
$evidenceToken = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'),([guid]::NewGuid().ToString('N').Substring(0,12))
$operationEvidenceRoot = Join-Path (Join-Path $PSScriptRoot 'Logs') "$evidencePrefix-$evidenceToken"
$invokeParameters = @{ ComputerName=$ComputerName; Printer=$Printer; DesiredState=$desiredState; SessionRoot=$operationEvidenceRoot }
if (-not [string]::IsNullOrWhiteSpace($PrintServer)) { $invokeParameters.PrintServer = $PrintServer }
if ($WhatIf) { $invokeParameters.WhatIf = $true }

$actionVerb = if ($Action -eq 'Map') { 'Mapping' } else { 'Unmapping' }
Write-Host ("{0} {1} queue(s) on {2} target(s). SYSTEM-WIDE for all users. No reachability sweep. No test page." -f $actionVerb,@($Printer).Count,@($ComputerName).Count) -ForegroundColor Cyan
$engineError = $null
try { $null = @(& $engine @invokeParameters *>&1) }
catch { $engineError = $_ }

$evidenceRoot = if (Test-Path -LiteralPath $operationEvidenceRoot -PathType Container) { $operationEvidenceRoot } else { $null }
$operationEvidenceAvailable = -not [string]::IsNullOrWhiteSpace($evidenceRoot) -and (Test-Path -LiteralPath (Join-Path $evidenceRoot 'Summary.json') -PathType Leaf)
if ($WhatIf) {
    if ($null -ne $engineError) { throw $engineError.Exception.Message }
    Write-Host 'PLAN: preview complete; no printer changes were made.' -ForegroundColor Green
    if ($operationEvidenceAvailable) { Write-Host ("Evidence: {0}" -f $evidenceRoot) -ForegroundColor DarkGray }
    return
}

$authoritativeSuccess = $operationEvidenceAvailable -and (Test-SasLatestAuthoritativePrinterProof -EvidenceRoot $evidenceRoot -DesiredState $desiredState)
if ($authoritativeSuccess) {
    if ($Action -eq 'Map') { Save-SasPrinterInteractionHistory -Computers @($ComputerName) -Printers @($Printer) -ExplicitPrintServer $explicitPrintServerForCache }
    Write-SasPrinterResult -Success $true -Action $Action -EvidenceRoot $evidenceRoot -RecoveredFromLowerLevelError:($null -ne $engineError)
    return
}
if ($null -ne $engineError -and -not $operationEvidenceAvailable) { throw $engineError.Exception.Message }
Write-SasPrinterResult -Success $false -Action $Action -EvidenceRoot $(if ($operationEvidenceAvailable) { $evidenceRoot } else { $null })
if ($operationEvidenceAvailable) { Write-SasPrinterFailureDiagnostic -EvidenceRoot $evidenceRoot }
if ($null -ne $engineError) { throw $engineError.Exception.Message }
throw 'Printer management returned without operation-scoped authoritative HKLM proof.'
