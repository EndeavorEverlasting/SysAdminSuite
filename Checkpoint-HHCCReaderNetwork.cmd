@echo off
setlocal EnableExtensions
title SysAdminSuite - H&H CC Reader Network Checkpoint
cls

if "%~1"=="" goto usage
if "%~2"=="" goto usage

set "PHASE=%~1"
set "RUN_ID=%~2"
set "EXPECTED_MAC=%~3"
set "LABEL=%~4"

if not exist "%~dp0scripts\Invoke-SasHhCcReaderNetworkCheckpoint.ps1" (
  echo ERROR: checkpoint implementation is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER NETWORK CHECKPOINT
echo ================================================================
echo  Phase: %PHASE%
echo  Run ID: %RUN_ID%
if not "%EXPECTED_MAC%"=="" echo  Expected MAC supplied: yes
if not "%LABEL%"=="" echo  Label: %LABEL%
echo.
echo  Read-only local capture: interface, IPv4/prefix, gateway, DNS,
echo  default route, Wi-Fi metadata when available, and exact-MAC cache.
echo  No reader contact. No network configuration change.
echo ================================================================
echo.

if "%EXPECTED_MAC%"=="" (
  "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-SasHhCcReaderNetworkCheckpoint.ps1" -Phase "%PHASE%" -RunId "%RUN_ID%" -Label "%LABEL%"
) else (
  "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-SasHhCcReaderNetworkCheckpoint.ps1" -Phase "%PHASE%" -RunId "%RUN_ID%" -ExpectedMac "%EXPECTED_MAC%" -Label "%LABEL%"
)
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   Checkpoint-HHCCReaderNetwork.cmd BEFORE_SWITCH^|AFTER_SWITCH^|MANUAL RUN_ID [EXPECTED_MAC] [LABEL]
echo.
echo Documentation-only example:
echo   Checkpoint-HHCCReaderNetwork.cmd AFTER_SWITCH DEMO-RUN AA-BB-CC-DD-EE-FF
exit /b 2
