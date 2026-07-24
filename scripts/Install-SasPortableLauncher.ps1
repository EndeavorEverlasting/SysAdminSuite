#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sourceLauncher = Join-Path $repoRoot 'scripts\SasPortableLauncher.ps1'
if (-not (Test-Path -LiteralPath $sourceLauncher -PathType Leaf)) {
    throw "Portable launcher source is missing: $sourceLauncher"
}

$installRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\bin'
$stateRoot = Split-Path -Parent $installRoot
$launcherDestination = Join-Path $installRoot 'SasPortableLauncher.ps1'
$cmdDestination = Join-Path $installRoot 'sas.cmd'
$cachePath = Join-Path $stateRoot 'repo-root.txt'

New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
Copy-Item -LiteralPath $sourceLauncher -Destination $launcherDestination -Force
Set-Content -LiteralPath $cachePath -Value $repoRoot -Encoding ASCII

$cmd = @'
@echo off
setlocal EnableExtensions
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0SasPortableLauncher.ps1" %*
endlocal & exit /b %ERRORLEVEL%
'@
Set-Content -LiteralPath $cmdDestination -Value $cmd -Encoding ASCII

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$segments = @($userPath -split ';' | ForEach-Object { $_.Trim().TrimEnd('\') } | Where-Object { $_ })
$alreadyPresent = @($segments | Where-Object { $_.Equals($installRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
if (-not $alreadyPresent) {
    $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $installRoot } else { $userPath.TrimEnd(';') + ';' + $installRoot }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
}

if (-not (($env:Path -split ';') -contains $installRoot)) {
    $env:Path = $env:Path.TrimEnd(';') + ';' + $installRoot
}

Write-Host 'SysAdminSuite portable operator command installed for the current Windows user.' -ForegroundColor Green
Write-Host "Resolved repo: $repoRoot"
Write-Host "Command: $cmdDestination"
Write-Host ''
Write-Host 'Open a new terminal and use:' -ForegroundColor Cyan
Write-Host '  sas autologon'
Write-Host '  sas network'
Write-Host '  sas cybernet Plan HOST'
Write-Host '  sas cybernet Apply HOST'
Write-Host '  sas cybernet Validate HOST'
Write-Host ''
Write-Host 'No administrator rights are required. Run this installer once for each Windows user/PC.'
