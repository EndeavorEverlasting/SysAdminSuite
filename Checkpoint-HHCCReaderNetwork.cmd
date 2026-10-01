@echo off
setlocal EnableExtensions EnableDelayedExpansion
title SysAdminSuite - H&H CC Reader Network Checkpoint
cls

if "%~1"=="" goto usage
if "%~2"=="" goto usage

set "PHASE=%~1"
set "RUN_ID=%~2"
set "EXPECTED_MAC=%~3"

if /I "!PHASE!"=="BEFORE_SWITCH" goto phase_ok
if /I "!PHASE!"=="AFTER_SWITCH" goto phase_ok
if /I "!PHASE!"=="MANUAL" goto phase_ok
goto usage

:phase_ok
>nul 2>&1 echo(!RUN_ID!| "%SystemRoot%\System32\findstr.exe" /R /X "[A-Za-z0-9_.:-][A-Za-z0-9_.:-]*"
if errorlevel 1 goto usage
if not "!EXPECTED_MAC!"=="" (
  >nul 2>&1 echo(!EXPECTED_MAC!| "%SystemRoot%\System32\findstr.exe" /R /X "[0-9A-Fa-f:-][0-9A-Fa-f:-]*"
  if errorlevel 1 goto usage
)

if not exist "%~dp0scripts\Invoke-SasHhCcReaderNetworkCheckpoint.ps1" (
  echo ERROR: checkpoint implementation is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER NETWORK CHECKPOINT
echo ================================================================
echo  Phase: !PHASE!
echo  Read-only local capture: interface, IPv4/prefix, gateway, DNS,
echo  default route, Wi-Fi metadata when available, and exact-MAC cache.
echo  No reader contact. No network configuration change.
echo ================================================================
echo.

if "!EXPECTED_MAC!"=="" (
  "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-SasHhCcReaderNetworkCheckpoint.ps1" -Phase "!PHASE!" -RunId "!RUN_ID!"
) else (
  "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-SasHhCcReaderNetworkCheckpoint.ps1" -Phase "!PHASE!" -RunId "!RUN_ID!" -ExpectedMac "!EXPECTED_MAC!"
)
exit /b !ERRORLEVEL!

:usage
echo Usage:
echo   Checkpoint-HHCCReaderNetwork.cmd BEFORE_SWITCH^|AFTER_SWITCH^|MANUAL RUN_ID [EXPECTED_MAC]
echo.
echo RUN_ID accepts letters, numbers, dot, underscore, colon, and hyphen only.
exit /b 2
