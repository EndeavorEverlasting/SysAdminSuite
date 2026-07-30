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

$parseTokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($sourceLauncher, [ref]$parseTokens, [ref]$parseErrors)
if (@($parseErrors).Count -gt 0) {
    throw "Portable launcher source has PowerShell parse errors; refusing to install: $sourceLauncher"
}

$installRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\bin'
$stateRoot = Split-Path -Parent $installRoot
$launcherDestination = Join-Path $installRoot 'SasPortableLauncher.ps1'
$cmdDestination = Join-Path $installRoot 'sas.cmd'
$cachePath = Join-Path $stateRoot 'repo-root.txt'

New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
Copy-Item -LiteralPath $sourceLauncher -Destination $launcherDestination -Force
Set-Content -LiteralPath $cachePath -Value $repoRoot -Encoding ASCII

# Keep the CMD shim deliberately small and stable. Before every invocation it checks the
# cached repo's tracked launcher. If that source has changed and parses cleanly, the shim
# refreshes the installed PowerShell dispatcher automatically. This prevents a repo update
# from leaving an older %LOCALAPPDATA% launcher silently missing newer commands.
$cmd = @'
@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "SAS_STATE=%LOCALAPPDATA%\SysAdminSuite"
set "SAS_CACHE=%LOCALAPPDATA%\SysAdminSuite\repo-root.txt"
set "SAS_INSTALLED=%~dp0SasPortableLauncher.ps1"

if exist "%SAS_CACHE%" (
  set "SAS_REPO="
  set /p SAS_REPO=<"%SAS_CACHE%"
  if defined SAS_REPO if exist "!SAS_REPO!\scripts\SasPortableLauncher.ps1" (
    set "SAS_SOURCE=!SAS_REPO!\scripts\SasPortableLauncher.ps1"
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$s=$env:SAS_SOURCE; $d=$env:SAS_INSTALLED; try { $t=$null; $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile($s,[ref]$t,[ref]$e); if (@($e).Count -gt 0) { Write-Warning 'Repo launcher changed but has parse errors; preserving installed launcher.'; exit 0 }; $copy=(-not (Test-Path -LiteralPath $d -PathType Leaf)); if (-not $copy) { $copy=((Get-FileHash -Algorithm SHA256 -LiteralPath $s).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $d).Hash) }; if ($copy) { Copy-Item -LiteralPath $s -Destination $d -Force; Write-Host 'sas launcher refreshed from cached SysAdminSuite repo.' -ForegroundColor DarkCyan } } catch { Write-Warning ('Could not self-refresh sas launcher; preserving installed copy. ' + $_.Exception.Message) }"
  )
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_INSTALLED%" %*
set "SAS_EXIT=!ERRORLEVEL!"
for %%# in (!SAS_EXIT!) do endlocal & exit /b %%#
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

Write-Host 'SysAdminSuite portable operator command installed/refreshed for the current Windows user.' -ForegroundColor Green
Write-Host "Resolved repo: $repoRoot"
Write-Host "Command: $cmdDestination"
Write-Host ''
Write-Host 'Open a new terminal and use:' -ForegroundColor Cyan
Write-Host '  sas                                      Show current deployment guidance'
Write-Host '  sas refresh                              Fetch current origin/main into an isolated field-ready worktree and refresh sas'
Write-Host '  sas cybernet Probe HOST                  Read-only one-target Kerberos SMB/Task Scheduler readiness'
Write-Host '  sas network HOST                         Alias for the same read-only readiness probe'
Write-Host '  sas cybernet Core HOST                   Five clinical apps only; profile before/after; AutoLogon untouched; no reboot'
Write-Host '  sas cybernet Deploy HOST                 Deploy full software profile; readiness included; AutoLogon last; restart included'
Write-Host '  sas autologon Remote HOST                Deploy AutoLogon only; restart included'
Write-Host '  sas evidence                             Find newest local readiness/deployment/runtime evidence; no network needed'
Write-Host '  sas evidence All                         List recent local evidence across known Desktop/OneDrive checkouts'
Write-Host '  sas cybernet Plan HOST                   Hardware-only Cybernet plan'
Write-Host '  sas cybernet Apply HOST                  Hardware-only Cybernet apply'
Write-Host '  sas cybernet Validate HOST               Hardware-only Cybernet validation'
Write-Host '  sas network                              Check approved Northwell network posture only'
Write-Host ''
Write-Host 'The installed sas shim now self-refreshes its dispatcher from the cached repo before every command.' -ForegroundColor Green
Write-Host 'Use `sas refresh` when you need the latest origin/main without touching or resetting an existing working tree.' -ForegroundColor Green
Write-Host 'Core deployment is Windows-native and does not require Git Bash or Python.' -ForegroundColor Green
Write-Host 'Core deployment preserves AutoLogon state and treats Imprivata as an observational conditional profile state.' -ForegroundColor Green
Write-Host 'Full deployment runs its own staged low-noise readiness gate before any target mutation.' -ForegroundColor Green
Write-Host 'The standalone Probe is optional diagnosis; it is not a prerequisite loop before Deploy.' -ForegroundColor Green
Write-Host 'Deployment completion includes the required target restart when AutoLogon is installed.' -ForegroundColor Green
Write-Host 'Fixture, live-cert, and runtime-proof loops are not prerequisites for software deployment completion.' -ForegroundColor Green
Write-Host 'If a terminal closes or crashes, use `sas evidence` before retrying anything.' -ForegroundColor Yellow
Write-Host 'Runtime proof remains available when explicitly requested, but it must not delay deployment.' -ForegroundColor Cyan
Write-Host ''
Write-Host 'No administrator rights are required to install/refresh the command itself. Run this installer once on older machines to upgrade the shim to the self-refreshing version.'
