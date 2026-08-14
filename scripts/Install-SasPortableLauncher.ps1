#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
$sourceLauncher = Join-Path -Path $repoRoot -ChildPath 'scripts\SasPortableLauncher.ps1'
$networkReturnCmd = Join-Path -Path $repoRoot -ChildPath 'Switch-Back-To-Previous-Network.cmd'
$autoLogonCmd = Join-Path -Path $repoRoot -ChildPath 'Run-AutoLogonOnsite.cmd'
$requiredOperatorScripts = @(
    $sourceLauncher,
    (Join-Path -Path $repoRoot -ChildPath 'scripts\SasOperatorSession.psm1'),
    (Join-Path -Path $repoRoot -ChildPath 'scripts\SasAutoLogonOperatorState.psm1'),
    (Join-Path -Path $repoRoot -ChildPath 'scripts\Show-SasOperatorContext.ps1'),
    (Join-Path -Path $repoRoot -ChildPath 'scripts\Return-SasOperatorToPreviousNetwork.ps1'),
    (Join-Path -Path $repoRoot -ChildPath 'scripts\SasBoundedNative.psm1'),
    (Join-Path -Path $repoRoot -ChildPath 'scripts\Recover-SasLatestInterruptedAutoLogonS4U.ps1'),
    (Join-Path -Path $repoRoot -ChildPath 'scripts\Complete-SasInterruptedAutoLogonS4URecovery.ps1'),
    (Join-Path -Path $repoRoot -ChildPath 'scripts\Invoke-SasAutoLogonOnsite.ps1'),
    (Join-Path -Path $repoRoot -ChildPath 'scripts\Invoke-SasAutoLogonFieldDeployment.ps1'),
    (Join-Path -Path $repoRoot -ChildPath 'scripts\Invoke-SasAutoLogonS4URestartDeployment.ps1'),
    (Join-Path -Path $repoRoot -ChildPath 'scripts\Invoke-SasAutoLogonKerberosS4UPilot.ps1'),
    (Join-Path -Path $repoRoot -ChildPath 'scripts\SasTargetNameResolution.psm1'),
    (Join-Path -Path $repoRoot -ChildPath 'scripts\SasSoftwareSourceIdentity.psm1'),
    (Join-Path -Path $repoRoot -ChildPath 'scripts\SasAutoLogonBaselinePolicy.psm1'),
    (Join-Path -Path $repoRoot -ChildPath 'scripts\Invoke-SasCybernetCoreRecovery.ps1'),
    (Join-Path -Path $repoRoot -ChildPath 'scripts\Invoke-SasCybernetProfiledClinicalCoreDeployment.ps1'),
    (Join-Path -Path $repoRoot -ChildPath 'scripts\Test-SasCybernetClinicalCoreSources.ps1')
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

$installRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'SysAdminSuite\bin'
$stateRoot = Split-Path -Parent $installRoot
$launcherDestination = Join-Path -Path $installRoot -ChildPath 'SasPortableLauncher.ps1'
$cmdDestination = Join-Path -Path $installRoot -ChildPath 'sas.cmd'
$leaveDestination = Join-Path -Path $installRoot -ChildPath 'sas-leave.cmd'
$cachePath = Join-Path -Path $stateRoot -ChildPath 'repo-root.txt'
New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
Copy-Item -LiteralPath $sourceLauncher -Destination $launcherDestination -Force
Set-Content -LiteralPath $cachePath -Value $repoRoot -Encoding ASCII

# Before every invocation, refresh the installed dispatcher from the cached repository only
# after the repository source parses. No optional cryptographic-hash cmdlet dependency is used.
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
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$s=$env:SAS_SOURCE; $d=$env:SAS_INSTALLED; try { $t=$null; $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile($s,[ref]$t,[ref]$e); if (@($e).Count -gt 0) { Write-Warning 'Repo launcher changed but has parse errors; preserving installed launcher.'; exit 0 }; Copy-Item -LiteralPath $s -Destination $d -Force } catch { Write-Warning ('Could not self-refresh sas launcher; preserving installed copy. ' + $_.Exception.Message) }"
  )
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_INSTALLED%" %*
set "SAS_EXIT=!ERRORLEVEL!"
for %%# in (!SAS_EXIT!) do endlocal & exit /b %%#
'@
Set-Content -LiteralPath $cmdDestination -Value $cmd -Encoding ASCII

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
Write-Host 'Supported field surfaces:' -ForegroundColor Cyan
Write-Host '  sas context                          Persistent repo/branch/network/target/recovery/deployment state'
Write-Host '  sas next                             Required network and one exact next command'
Write-Host '  sas cybernet Probe HOST             PROTECTED NORTHWELL: optional read-only readiness'
Write-Host '  sas cybernet Deploy HOST            PROTECTED NORTHWELL: full Cybernet software profile; readiness included; AutoLogon last; restart included'
Write-Host '  sas autologon Remote HOST           Canonicalize, recover safe probe-only state, apply AutoLogon once, restart'
Write-Host '  sas autologon Recover HOST          Recovery only; never install AutoLogon'
Write-Host '  sas network                          Read-only approved Northwell network posture'
Write-Host '  sas network HOST                     Optional read-only target readiness probe'
Write-Host ''
Write-Host 'The standalone Probe is optional diagnosis; it is not a prerequisite loop before Deploy' -ForegroundColor Green
Write-Host 'Fixture/live-cert/runtime-proof loops are NOT prerequisites for deployment.' -ForegroundColor Green
Write-Host 'The installed sas shim self-refreshes from the cached field-ready repo on every install/refresh without an optional cryptographic-hash cmdlet.' -ForegroundColor Green
Write-Host 'Core is already separate. AutoLogon Remote never deploys the five clinical-core applications.' -ForegroundColor Green
Write-Host 'If a terminal closes, use sas context or sas next. Do not reconstruct task or recovery fragments.' -ForegroundColor Yellow
