@echo off
setlocal EnableExtensions EnableDelayedExpansion
title SysAdminSuite - H^&H CC Reader Home-Lab Discovery
cls

if "%~1"=="" goto usage
if /I not "%~2"=="CONFIRM_CONSUMER_LAB" goto usage

set "RUN_ID=%~1"
set "EXPECTED_MAC=%~3"

echo(!RUN_ID!| "%SystemRoot%\System32\findstr.exe" /R /X "[A-Za-z0-9_.:-][A-Za-z0-9_.:-]*" >nul
if errorlevel 1 goto usage
if not "!EXPECTED_MAC!"=="" (
  echo(!EXPECTED_MAC!| "%SystemRoot%\System32\findstr.exe" /R /X "[0-9A-Fa-f:-][0-9A-Fa-f:-]*" >nul
  if errorlevel 1 goto usage
)

if not exist "%~dp0scripts\Invoke-SasHhCcReaderHomeLabDiscovery.ps1" (
  echo ERROR: home-lab discovery implementation is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER HOME-LAB DISCOVERY
echo ================================================================
echo  Environment contract: AUTHORIZED_CONSUMER_LAB ^(explicitly confirmed^)
echo  Scope: current private local subnet only, bounded host-presence
echo  discovery, exact-MAC correlation, then the existing canonical probe.
echo.
echo  This command does not change reader or workstation network settings.
echo  It does not perform broad port scanning, credential guessing, ADB,
echo  firmware mutation, or payment actions.
echo ================================================================
echo.

if "!EXPECTED_MAC!"=="" (
  "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-SasHhCcReaderHomeLabDiscovery.ps1" -RunId "!RUN_ID!" -ConfirmConsumerLab
) else (
  "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-SasHhCcReaderHomeLabDiscovery.ps1" -RunId "!RUN_ID!" -ConfirmConsumerLab -ExpectedMac "!EXPECTED_MAC!"
)
exit /b !ERRORLEVEL!

:usage
echo Usage:
echo   Discover-HHCCReaderHomeLab.cmd RUN_ID CONFIRM_CONSUMER_LAB [EXPECTED_MAC]
echo.
echo This lane requires a prepared C:\SASAL runtime for the same RUN_ID.
echo RUN_ID accepts letters, numbers, dot, underscore, colon, and hyphen only.
exit /b 2
