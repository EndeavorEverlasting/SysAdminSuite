#Requires -Version 5.1
<#
.SYNOPSIS
Run the canonical AutoLogon-only deployment while guaranteeing contiguous operator-facing stage numbers.

.DESCRIPTION
This is a presentation wrapper around the registered `sas autologon Remote HOST` command. It does
not implement AutoLogon, change network policy, alter target state directly, or reinterpret success.
It streams the canonical command's output through SasAutoLogonProgress.psm1 so a forward stage jump
is made explicit with truthful SKIP records. The canonical command's exit code is propagated unchanged.
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

$candidates = New-Object 'System.Collections.Generic.List[string]'
$resolved = Get-Command sas.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($resolved -and -not [string]::IsNullOrWhiteSpace([string]$resolved.Source)) {
    [void]$candidates.Add([IO.Path]::GetFullPath([string]$resolved.Source))
}
foreach ($candidate in @(
    'C:\ProgramData\SysAdminSuite\bin\sas.cmd',
    (Join-Path $env:LOCALAPPDATA 'SysAdminSuite\bin\sas.cmd')
)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) {
        try { $full = [IO.Path]::GetFullPath([string]$candidate) } catch { continue }
        if (-not $candidates.Contains($full)) { [void]$candidates.Add($full) }
    }
}

$sasCommand = $null
foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $sasCommand = $candidate
        break
    }
}
if ([string]::IsNullOrWhiteSpace($sasCommand)) {
    throw 'Canonical sas.cmd launcher was not found. Refresh/install the tracked SysAdminSuite launcher before deployment.'
}

Write-Host 'AUTOLOGON PROGRESS CONTINUITY: ENABLED' -ForegroundColor Cyan
Write-Host "Canonical command: sas autologon Remote $target" -ForegroundColor Cyan
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
