#Requires -Version 5.1
<#
.SYNOPSIS
Compatibility entrypoint for the approved software install workflow.

.DESCRIPTION
The technician operator implementation is Start-SasApprovedSoftwareOperator.ps1. This file
preserves the previous Auto Didact entrypoint name while forwarding only declared parameters.
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'ListPackages', 'Before', 'Plan', 'Install', 'After', 'Acceptance', 'OpenLatest')]
    [string]$Action = 'Menu',

    [string]$TargetsCsv,
    [string]$PackageId,
    [string[]]$InstallerArguments = @(),
    [string[]]$ProcessName = @(),
    [string]$WindowTitlePattern,
    [string]$OutputRoot,

    [ValidateRange(1, 25)]
    [int]$MaxTargets = 25,

    [switch]$ApplicationObserved,
    [switch]$AutoLogonObservedAfterReboot,
    [switch]$FixtureMode,
    [switch]$NonInteractive,
    [switch]$NoOpen
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$operator = Join-Path $PSScriptRoot 'Start-SasApprovedSoftwareOperator.ps1'
if (-not (Test-Path -LiteralPath $operator -PathType Leaf)) {
    throw "Approved software operator wrapper not found: $operator"
}

$forward = @{}
foreach ($name in $PSBoundParameters.Keys) {
    $forward[$name] = $PSBoundParameters[$name]
}

& $operator @forward
