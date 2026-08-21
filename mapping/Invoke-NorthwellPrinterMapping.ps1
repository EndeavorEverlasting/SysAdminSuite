<#
.SYNOPSIS
    Compatibility wrapper for Northwell system-wide printer mapping.

.DESCRIPTION
    Preserves the existing mapping command surface while delegating to the
    reversible state engine with DesiredState=Present.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)][Alias('Computer','Computers','HostName','HostNames')][ValidateNotNullOrEmpty()][string[]]$ComputerName,
    [Parameter(Mandatory)][Alias('Queue','Queues','PrinterQueue','PrinterQueues')][ValidateNotNullOrEmpty()][string[]]$Printer,
    [string]$PrintServer,
    [string]$DnsSuffix = 'nslijhs.net',
    [ValidateRange(15,600)][int]$TimeoutSeconds = 120,
    [switch]$KeepRemoteArtifacts,
    [string]$SessionRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$engine = Join-Path $PSScriptRoot 'Invoke-NorthwellPrinterState.ps1'
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw "Canonical reversible printer state engine not found: $engine" }

$invoke = @{
    ComputerName = $ComputerName
    Printer = $Printer
    DesiredState = 'Present'
    DnsSuffix = $DnsSuffix
    TimeoutSeconds = $TimeoutSeconds
}
if (-not [string]::IsNullOrWhiteSpace($PrintServer)) { $invoke.PrintServer = $PrintServer }
if ($KeepRemoteArtifacts) { $invoke.KeepRemoteArtifacts = $true }
if (-not [string]::IsNullOrWhiteSpace($SessionRoot)) { $invoke.SessionRoot = $SessionRoot }
if ($WhatIfPreference) { $invoke.WhatIf = $true }

& $engine @invoke
