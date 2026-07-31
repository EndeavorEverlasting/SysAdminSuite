#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sourceLauncher = Join-Path $repoRoot 'scripts\SasPortableLauncher.ps1'
$networkReturnCmd = Join-Path $repoRoot 'Switch-Back-To-Previous-Network.cmd'
$autoLogonCmd = Join-Path $repoRoot 'Run-AutoLogonOnsite.cmd'
$requiredOperatorScripts = @(
    $sourceLauncher,
    (Join-Path $repoRoot 'scripts\SasOperatorSession.psm1'),
    (Join-Path $repoRoot 'scripts\Show-SasOperatorContext.ps1'),
    (Join-Path $repoRoot 'scripts\Return-SasOperatorToPreviousNetwork.ps1'),
    (Join-Path $repoRoot 'scripts\SasBoundedNative.psm1'),
    (Join-Path $repoRoot 'scripts\Recover-SasLatestInterruptedAutoLogonS4U.ps1'),
    (Join-Path $repoRoot 'scripts\Complete-SasInterruptedAutoLogonS4URecovery.ps1'),
    (Join-Path $repoRoot 'scripts\Invoke-SasAutoLogonOnsite.ps1'),
    (Join-Path $repoRoot 'scripts\Invoke-SasAutoLogonS4URestartDeployment.ps1'),
    (Join-Path $repoRoot 'scripts\Invoke-SasAutoLogonKerberosS4UPilot.ps1'),
    (Join-Path $repoRoot 'scripts\SasSoftwareSourceIdentity.psm1'),
    (Join-Path $repoRoot 'scripts\SasAutoLogonBaselinePolicy.psm1'),
    (Join-Path $repoRoot 'scripts\Invoke-SasCybernetCoreRecovery.ps1'),
    (Join-Path $repoRoot 'scripts\Invoke-SasCybernetProfiledClinicalCoreDeployment.ps1'),
    (Join-Path $repoRoot 'scripts\Test-SasCybernetClinicalCoreSources.ps1')
)
foreach ($scriptPath in $requiredOperatorScripts) {
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "Required operator script is missing: $scriptPath" }
    $parseTokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$parseTokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) { throw "Operator script has PowerShell parse errors; refusing to install: $scriptPath :: $($parseErrors[0].Message)" }
}
foreach ($cmdPath in @($networkReturnCmd,$autoLogonCmd)) {
    if (-not (Test-Path -LiteralPath $cmdPath -PathType Leaf)) { throw "Required operator command is missing: $cmdPath" }
}

$installRoot = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\bin'
$stateRoot = Split-Path -Parent $installRoot
$launcherDestination = Join-Path $installRoot 'SasPortableLauncher.ps1'
$cmdDestination = Join-Path $installRoot 'sas.cmd'
$leaveDestination = Join-Path $installRoot 'sas-leave.cmd'
$cachePath = Join-Path $stateRoot 'repo-root.txt'
New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
Copy-Item -LiteralPath $sourceLauncher -Destination $launcherDestination -Force
Set-Content -LiteralPath $cachePath -Value $repoRoot -Encoding ASCII

# Keep the CMD shim deliberately small and stable. Before every invocation it checks the
# cached repo's tracked launcher. If that source changed and parses cleanly, the shim
# refreshes the installed PowerShell dispatcher automatically. The operator-facing command
# therefore behaves the same from CMD and PowerShell and does not depend on shell variables.
$cmd = @'
@echo off
setlocal EnableExtensions EnableDelayedExpansion
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

# This installed CMD is intentionally double-clickable. It delegates to the same repo-owned
# `sas leave` path as the terminal surface and therefore never embeds SSIDs or credentials.
$leaveCmd = @'
@echo off
setlocal EnableExtensions
call "%~dp0sas.cmd" leave
set "SAS_EXIT=%ERRORLEVEL%"
echo.
pause
for %%# in (%SAS_EXIT%) do endlocal & exit /b %%#
'@
Set-Content -LiteralPath $leaveDestination -Value $leaveCmd -Encoding ASCII

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$segments = @($userPath -split ';' | ForEach-Object { $_.Trim().TrimEnd('\') } | Where-Object { $_ })
$alreadyPresent = @($segments | Where-Object { $_.Equals($installRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
if (-not $alreadyPresent) {
    $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $installRoot } else { $userPath.TrimEnd(';') + ';' + $installRoot }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
}
if (-not (($env:Path -split ';') -contains $installRoot)) { $env:Path = $env:Path.TrimEnd(';') + ';' + $installRoot }

Write-Host 'SysAdminSuite portable operator command installed/refreshed for the current Windows user.' -ForegroundColor Green
Write-Host "Resolved repo: $repoRoot"
Write-Host "Command: $cmdDestination"
Write-Host "Double-click network return: $leaveDestination"
Write-Host ''
Write-Host 'Open either CMD or PowerShell and use:' -ForegroundColor Cyan
Write-Host '  sas context                          Show persistent repo/network/target/lane/run/cleanup state'
Write-Host '  sas next                             Show only the required network and one next command'
Write-Host '  sas refresh                          GUEST / INTERNET: refresh current tracked branch field-ready checkout'
Write-Host '  sas leave                            LOCAL ONLY: return to recorded previous guest/internet Wi-Fi'
Write-Host '  sas cybernet Core HOST              PROTECTED NORTHWELL: five clinical apps; AutoLogon preserved; no reboot'
Write-Host '  sas cybernet Recover HOST           PROTECTED NORTHWELL: exact prior-run Cybernet cleanup/recovery only'
Write-Host '  sas cybernet Probe HOST             PROTECTED NORTHWELL: optional read-only readiness'
Write-Host '  sas evidence Cybernet               OFFLINE: recover newest Cybernet run evidence and next action'
Write-Host '  sas cybernet Deploy HOST            PROTECTED NORTHWELL: full profile; readiness included; AutoLogon last; restart included'
Write-Host '  sas autologon Remote HOST           PROTECTED NORTHWELL: recover recorded probe interruption, AutoLogon-only apply, restart'
Write-Host '  sas autologon Recover HOST          PROTECTED NORTHWELL: recover recorded probe-only interruptions; no install'
Write-Host '  sas network                          Read-only approved Northwell network posture'
Write-Host ''
Write-Host 'The installed sas shim self-refreshes its dispatcher from the cached field-ready repo before every command.' -ForegroundColor Green
Write-Host 'operator-session.json remains machine-local under %LOCALAPPDATA%\SysAdminSuite and survives terminal/shell changes.' -ForegroundColor Green
Write-Host 'Core is one Windows-native transaction: recovery, source preflight, staging, SYSTEM execution, profile capture, evidence, and cleanup.' -ForegroundColor Green
Write-Host 'Core never installs/enables/repairs AutoLogon and never manages Imprivata. Core never performs an automatic reboot.' -ForegroundColor Green
Write-Host 'AutoLogon Remote performs its local interrupted-run gate before a new apply; do not reconstruct recovery fragments.' -ForegroundColor Green
Write-Host 'Full deployment retains readiness included, AutoLogon last, and restart included behavior.' -ForegroundColor Green
Write-Host 'The standalone Probe is optional diagnosis; it is not a prerequisite loop before Deploy.' -ForegroundColor Green
Write-Host 'If a terminal closes or crashes, use `sas context` or `sas next`; do not reconstruct try/catch/finally fragments.' -ForegroundColor Yellow
Write-Host ''
Write-Host 'No administrator rights are required to install/refresh the operator command itself.'
