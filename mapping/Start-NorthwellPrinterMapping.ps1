<#
.SYNOPSIS
    Interactive technician front-end for Northwell system-wide printer mapping.

.DESCRIPTION
    Collects target PC hostname(s) and one or more print-server/queue sets, then
    delegates validation, SYSTEM execution, machine-wide proof, cleanup, and
    evidence to Invoke-NorthwellPrinterMapping.ps1.

    Optional operator-local defaults may be stored in:
        Config\northwell-printer-defaults.local.json

    That file is gitignored. Tracked repository content contains only synthetic
    placeholders; no live print-server or queue endpoint is a source-controlled
    automatic default.
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

$repoRoot = Split-Path -Parent $PSScriptRoot
$localDefaultsPath = Join-Path $repoRoot 'Config\northwell-printer-defaults.local.json'

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
    if ($server -match '(?i)REPLACE-WITH|EXAMPLE' -or $queue -match '(?i)REPLACE-WITH|EXAMPLE') {
        return $null
    }

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
    $setNumber = 0
    $firstSet = $true

    do {
        $setNumber++
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

        Write-Host ''
        Write-Host "Printer set $setNumber" -ForegroundColor Cyan
        if ($firstSet -and $null -ne $LocalDefaults) {
            Write-Host 'Operator-local default is configured. Press Enter to accept the bracketed value.' -ForegroundColor Green
        }
        elseif ($firstSet) {
            Write-Host 'No operator-local printer default is configured. Use Edit-NorthwellPrinter-Defaults.cmd if you want one.' -ForegroundColor DarkGray
        }
        Write-Host 'Type AD as the server to resolve queue-only names through Active Directory.' -ForegroundColor DarkGray

        $serverPrompt = if ([string]::IsNullOrWhiteSpace($serverDefault)) { 'Print server hostname (or AD)' } else { "Print server hostname [$serverDefault]" }
        $rawServer = Read-Host $serverPrompt
        if ([string]::IsNullOrWhiteSpace($rawServer)) {
            if ([string]::IsNullOrWhiteSpace($serverDefault)) { throw 'Print server cannot be blank. Enter a hostname or type AD for queue-only directory resolution.' }
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
        $queues = @(Split-SasFieldList -Value $rawQueues -Label 'Printer queue')

        foreach ($queue in $queues) {
            if ($queue.StartsWith('\\') -or $queue.StartsWith('//')) {
                $collected.Add($queue)
            }
            elseif ([string]::IsNullOrWhiteSpace($server)) {
                $collected.Add($queue)
            }
            else {
                $collected.Add(('\\{0}\{1}' -f $server, $queue))
            }
        }

        $firstSet = $false
        Write-Host ''
        $more = Read-Host 'Add another print server / queue set? [y/N]'
    } while ($more -match '^(?i:y|yes)$')

    return $collected.ToArray()
}

if (-not $ComputerName -or $ComputerName.Count -eq 0) {
    Write-Host ''
    Write-Host 'Northwell System-Wide Printer Mapping' -ForegroundColor Cyan
    Write-Host '-------------------------------------' -ForegroundColor Cyan
    Write-Host 'Enter target PC hostnames only (not IP addresses).' -ForegroundColor Yellow
    Write-Host 'You may map one PC or paste several, separated by commas or semicolons.' -ForegroundColor DarkGray
    $rawComputers = Read-Host 'Target PC hostname(s), comma-separated'
    $ComputerName = @(Split-SasFieldList -Value $rawComputers -Label 'Target PC hostname')
}

if (-not $Printer -or $Printer.Count -eq 0) {
    $localDefaults = Get-SasNorthwellPrinterLocalDefaults
    $Printer = @(Read-SasNorthwellPrinterSets -InitialPrintServer $PrintServer -LocalDefaults $localDefaults)
    # Interactive collection has already converted explicit server + queue pairs to UNC.
    # Clearing this only after using InitialPrintServer avoids applying one server twice.
    $PrintServer = $null
}

$guardModule = Join-Path $repoRoot 'scripts\SasNetworkGuard.psm1'
if (-not (Test-Path -LiteralPath $guardModule -PathType Leaf)) {
    throw "Shared Northwell network guard not found: $guardModule"
}

if (-not $WhatIf) {
    Import-Module $guardModule -Force -ErrorAction Stop
    Assert-SasNorthwellWifi
    Write-Host 'Approved Northwell network posture detected. Guest Wi-Fi may remain connected when a live DomainAuthenticated VPN/LAN path is active.' -ForegroundColor Green
}

$engine = Join-Path $PSScriptRoot 'Invoke-NorthwellPrinterMapping.ps1'
if (-not (Test-Path -LiteralPath $engine)) { throw "Canonical printer engine not found: $engine" }

$invokeParameters = @{
    ComputerName = $ComputerName
    Printer = $Printer
}
if (-not [string]::IsNullOrWhiteSpace($PrintServer)) { $invokeParameters.PrintServer = $PrintServer }
if ($WhatIf) { $invokeParameters.WhatIf = $true }

Write-Host ''
Write-Host 'Client requirement: this run maps printers SYSTEM-WIDE for all users.' -ForegroundColor Green
Write-Host ('Targets : {0}' -f ($ComputerName -join ', ')) -ForegroundColor Cyan
Write-Host ('Printers: {0}' -f ($Printer -join ', ')) -ForegroundColor Cyan
Write-Host 'The run is successful only after SYSTEM identity and HKLM machine-wide queue proof.' -ForegroundColor Green
Write-Host ''

& $engine @invokeParameters
