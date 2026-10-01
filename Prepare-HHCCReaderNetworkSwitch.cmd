@echo off
setlocal EnableExtensions EnableDelayedExpansion
title SysAdminSuite - H&H CC Reader Network Switch Prepare
cls

if "%~1"=="" goto usage
set "RUN_ID=%~1"
set "EXPECTED_MAC=%~2"
set "SAS_EXIT=1"

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER NETWORK-SWITCH PREPARE
echo ================================================================
echo  Run ID: %RUN_ID%
if not "%EXPECTED_MAC%"=="" echo  Expected MAC supplied: yes
echo.
echo  Purpose:
echo    1. refresh and seal current SysAdminSuite to C:\SASAL
echo    2. capture the current workstation network as BEFORE_SWITCH
echo    3. preserve a machine-local state file for the after-switch lane
echo.
echo  This command does NOT change the reader or choose the next network.
echo ================================================================
echo.

if not exist "%~dp0scripts\Invoke-SasNetworkAwareField.ps1" (
  echo ERROR: canonical network-aware refresh entrypoint is missing.
  set "SAS_EXIT=1"
  goto finish
)

echo Refreshing provider/current main and sealing C:\SASAL...
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-SasNetworkAwareField.ps1" refresh
set "SAS_EXIT=!ERRORLEVEL!"
if not "!SAS_EXIT!"=="0" goto finish

if not exist "C:\SASAL\Checkpoint-HHCCReaderNetwork.cmd" (
  echo ERROR: refreshed sealed runtime is missing Checkpoint-HHCCReaderNetwork.cmd.
  set "SAS_EXIT=1"
  goto finish
)

if "%EXPECTED_MAC%"=="" (
  call "C:\SASAL\Checkpoint-HHCCReaderNetwork.cmd" BEFORE_SWITCH "%RUN_ID%"
) else (
  call "C:\SASAL\Checkpoint-HHCCReaderNetwork.cmd" BEFORE_SWITCH "%RUN_ID%" "%EXPECTED_MAC%"
)
set "SAS_EXIT=!ERRORLEVEL!"
if not "!SAS_EXIT!"=="0" goto finish

echo.
echo PREPARE_COMPLETE
echo After the network switch, run:
echo   C:\SASAL\Discover-HHCCReaderHomeLab.cmd "%RUN_ID%"
echo.
echo Optional explicit after-switch checkpoint only:
echo   C:\SASAL\Checkpoint-HHCCReaderNetwork.cmd AFTER_SWITCH "%RUN_ID%"
goto finish

:usage
echo Usage:
echo   Prepare-HHCCReaderNetworkSwitch.cmd RUN_ID [EXPECTED_MAC]
echo.
echo Documentation-only example:
echo   Prepare-HHCCReaderNetworkSwitch.cmd DEMO-RUN AA-BB-CC-DD-EE-FF
set "SAS_EXIT=2"

:finish
if not "!SAS_EXIT!"=="0" (
  echo.
  echo H^&H CC-reader network-switch preparation did not complete.
)
endlocal & exit /b %SAS_EXIT%
