#Requires -Version 5.1
<#
.SYNOPSIS
Run the canonical AutoLogon-only deployment while guaranteeing contiguous operator-facing stage numbers.

.DESCRIPTION
This is a presentation wrapper around the registered `sas autologon Remote HOST` command. It does
not implement AutoLogon, change network policy, alter target state directly, or reinterpret success.
It invokes only the tracked installed `sas.cmd` launcher locations, streams that canonical route's
output through SasAutoLogonProgress.psm1, and propagates the canonical command's exit code unchanged.
Checkout/cache/PATH fallbacks are intentionally not execution authority for protected field deployment.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$target = $ComputerName.Trim()
if ($target -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') {
    throw "Invalid AutoLogon target name: $target"
}

$progressModule = Join-Path $PSScriptRoot 'SasAutoLogonProgress.psm1'
if (-not (Test-Path -LiteralPath $progressModule -PathType Leaf)) {
    throw "AutoLogon progress module is missing: $progressModule"
}
Import-Module $progressModule -Force

$machineLauncher = [IO.Path]::GetFullPath('C:\ProgramData\SysAdminSuite\bin\sas.cmd')
$userLauncher = $null
if (-not [string]::IsNullOrWhiteSpace([string]$env:LOCALAPPDATA)) {
    $userLauncher = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'SysAdminSuite\bin\sas.cmd'))
}

$sasCommand = $null
foreach ($candidate in @($machineLauncher,$userLauncher)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and
        (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        $sasCommand = [string]$candidate
        break
    }
}
if ([string]::IsNullOrWhiteSpace($sasCommand)) {
    throw 'Canonical installed sas.cmd launcher was not found. Refresh/install the tracked SysAdminSuite launcher before deployment; checkout, cache, and PATH fallbacks are not accepted.'
}

Write-Host 'AUTOLOGON PROGRESS CONTINUITY: ENABLED' -ForegroundColor Cyan
Write-Host "Canonical command: sas autologon Remote $target" -ForegroundColor Cyan
Write-Host "Installed launcher: $sasCommand" -ForegroundColor Cyan
Write-Host 'Missing numbered stages, if any, will be printed explicitly as SKIP; deployment semantics are unchanged.' -ForegroundColor Cyan
Write-Host ''

$global:LASTEXITCODE = 0
& $sasCommand autologon Remote $target 2>&1 | ConvertTo-SasAutoLogonContiguousProgress | ForEach-Object {
    Write-Host ([string]$_)
}
$exitCode = [int]$global:LASTEXITCODE
if ($exitCode -ne 0) {
    Write-Host "AUTOLOGON COMMAND EXIT: $exitCode" -ForegroundColor Yellow
}
exit $exitCode
