<#
.SYNOPSIS
    Interactive technician front-end for Northwell system-wide printer mapping.

.DESCRIPTION
    Collects only the two field inputs technicians normally have: target PC
    hostname(s) and printer queue(s). Delegates all validation, directory
    resolution, SYSTEM execution, machine-wide proof, cleanup, and evidence to
    Invoke-NorthwellPrinterMapping.ps1.
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

if (-not $ComputerName -or $ComputerName.Count -eq 0) {
    Write-Host ''
    Write-Host 'Northwell System-Wide Printer Mapping' -ForegroundColor Cyan
    Write-Host '-------------------------------------' -ForegroundColor Cyan
    Write-Host 'Enter target PC hostnames only (not IP addresses).' -ForegroundColor Yellow
    $rawComputers = Read-Host 'Target PC hostname(s), comma-separated'
    $ComputerName = @(Split-SasFieldList -Value $rawComputers -Label 'Target PC hostname')
}

if (-not $Printer -or $Printer.Count -eq 0) {
    Write-Host ''
    Write-Host 'Enter a shared queue as \\server\queue, //server/queue, or queue name only.' -ForegroundColor Yellow
    Write-Host 'Do NOT enter a printer IP address.' -ForegroundColor Yellow
    $rawPrinters = Read-Host 'Printer queue(s), comma-separated'
    $Printer = @(Split-SasFieldList -Value $rawPrinters -Label 'Printer queue')
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
Write-Host 'The run is successful only after SYSTEM identity and HKLM machine-wide queue proof.' -ForegroundColor Green
Write-Host ''

& $engine @invokeParameters
