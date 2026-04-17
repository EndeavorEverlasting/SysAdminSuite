<#
.SYNOPSIS
    Lists Windows optional features (DISM / Get-WindowsOptionalFeature) on this PC.

.DESCRIPTION
    Read-only audit for field use: writes a text report under GetInfo\Output\QRTasks.
    Requires an elevated session for -Online queries on most Windows 10/11 builds.

.PARAMETER IncludeDisabled
    If set, lists features that are Disabled or Absent as well as Enabled.

.NOTES
    Part of SysAdminSuite -- QRTasks extension module.
    PowerShell 5.1+ on Windows client OS with DISM optional component stack.
#>
param(
    [switch]$IncludeDisabled
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$_outDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'GetInfo\Output\QRTasks'
if (-not (Test-Path -LiteralPath $_outDir)) {
    New-Item -ItemType Directory -Path $_outDir -Force | Out-Null
}
$outFile = Join-Path $_outDir "WindowsOptionalFeatures_$($env:COMPUTERNAME).txt"

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Windows Optional Features -- $env:COMPUTERNAME -- $timestamp")
$lines.Add(('=' * 80))
$lines.Add('')
if (-not (Test-IsAdmin)) {
    $lines.Add('WARNING: Session is not elevated. Get-WindowsOptionalFeature -Online may fail.')
    $lines.Add('Re-run PowerShell as Administrator for a full inventory.')
    $lines.Add('')
}

try {
    $feat = Get-WindowsOptionalFeature -Online -ErrorAction Stop
    if (-not $IncludeDisabled) {
        $feat = $feat | Where-Object { $_.State -eq 'Enabled' }
    }
    $feat = $feat | Sort-Object FeatureName
    $lines.Add("Count: $($feat.Count)")
    $lines.Add('')
    foreach ($f in $feat) {
        $lines.Add(('{0,-50} {1}' -f $f.FeatureName, $f.State))
    }
} catch {
    $lines.Add("ERROR: $($_.Exception.Message)")
    $lines.Add('')
    $lines.Add('Tip: Open an elevated PowerShell and re-run this task, or use:')
    $lines.Add('  DISM /Online /Get-Features /Format:Table')
}

$lines.Add('')
$lines.Add(('=' * 80))
$lines.Add("Output: $outFile")

$text = ($lines -join [Environment]::NewLine)
$text | Out-File -LiteralPath $outFile -Encoding UTF8
Write-Host $text
