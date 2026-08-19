<#
.SYNOPSIS
    Interactive technician front-end for Northwell system-wide printer mapping.

.DESCRIPTION
    Collects target PC hostname(s) and one or more print-server/queue sets, then
    delegates validation, SYSTEM execution, machine-wide proof, cleanup, and
    evidence to Invoke-NorthwellPrinterMapping.ps1.

    A known field-proven Northwell example is offered as the interactive default:
        \\SYKPNHPHPS01V\LS001-EMS01

    Pressing Enter at both printer prompts explicitly accepts that example. It is
    never silently applied to a target because target PC hostname input is always
    required first.
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

$defaultPrintServer = 'SYKPNHPHPS01V'
$defaultPrinterQueue = 'LS001-EMS01'

function Split-SasFieldList {
    param(
        [Parameter(Mandatory)]
        [string]$Value,
        [Parameter(Mandatory)]
        [string]$Label
    )

    $items = @(
        $Value -split '\s*[,;\r\n]+\s*' |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($items.Count -eq 0) {
        throw "$Label cannot be blank."
    }
    return $items
}

function Read-SasNorthwellPrinterSets {
    $collected = New-Object System.Collections.Generic.List[string]
    $setNumber = 0

    do {
        $setNumber++
        Write-Host ''
        Write-Host "Printer set $setNumber" -ForegroundColor Cyan
        Write-Host "Known field-proven example: \\$defaultPrintServer\$defaultPrinterQueue" -ForegroundColor Green
        Write-Host 'Press Enter at both prompts to use that example.' -ForegroundColor DarkGray
        Write-Host 'Type AD as the server to resolve queue-only names through Active Directory.' -ForegroundColor DarkGray

        $rawServer = Read-Host "Print server hostname [$defaultPrintServer]"
        if ([string]::IsNullOrWhiteSpace($rawServer)) {
            $server = $defaultPrintServer
        }
        elseif ($rawServer.Trim().Equals('AD', [System.StringComparison]::OrdinalIgnoreCase)) {
            $server = ''
        }
        else {
            $server = $rawServer.Trim()
        }

        $rawQueues = Read-Host "Queue name(s), comma-separated [$defaultPrinterQueue]"
        if ([string]::IsNullOrWhiteSpace($rawQueues)) {
            $rawQueues = $defaultPrinterQueue
        }
        $queues = @(Split-SasFieldList -Value $rawQueues -Label 'Printer queue')

        foreach ($queue in $queues) {
            if ($queue.StartsWith('\\') -or $queue.StartsWith('//')) {
                $collected.Add($queue)
                continue
            }
            if ([string]::IsNullOrWhiteSpace($server)) {
                $collected.Add($queue)
                continue
            }
            $collected.Add(('\\{0}\{1}' -f $server, $queue))
        }

        Write-Host ''
        $more = Read-Host 'Add another print server / queue set? [y/N]'
    } while ($more -match '^(?i:y|yes)$')

    return @($collected | Sort-Object -Unique)
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
    $Printer = @(Read-SasNorthwellPrinterSets)
    $PrintServer = $null
}

$repoRoot = Split-Path -Parent $PSScriptRoot
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
if (-not (Test-Path -LiteralPath $engine)) {
    throw "Canonical printer engine not found: $engine"
}

$invokeParameters = @{
    ComputerName = $ComputerName
    Printer = $Printer
}
if (-not [string]::IsNullOrWhiteSpace($PrintServer)) {
    $invokeParameters.PrintServer = $PrintServer
}
if ($WhatIf) {
    $invokeParameters.WhatIf = $true
}

Write-Host ''
Write-Host 'Client requirement: this run maps printers SYSTEM-WIDE for all users.' -ForegroundColor Green
Write-Host ('Targets : {0}' -f ($ComputerName -join ', ')) -ForegroundColor Cyan
Write-Host ('Printers: {0}' -f ($Printer -join ', ')) -ForegroundColor Cyan
Write-Host 'The run is successful only after SYSTEM identity and HKLM machine-wide queue proof.' -ForegroundColor Green
Write-Host ''

& $engine @invokeParameters
