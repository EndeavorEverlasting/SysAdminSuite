@echo off
setlocal EnableExtensions
title SysAdminSuite - Return to Previous Network
set "SCRIPT_DIR=%~dp0"

echo.
echo ==================================================
echo  SYSADMINSUITE - RETURN TO PREVIOUS NETWORK
echo ==================================================
echo This changes only the local workstation Wi-Fi profile.
echo It does not contact or modify a deployment target.
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Return-SasOperatorToPreviousNetwork.ps1"
set "EXITCODE=%ERRORLEVEL%"

echo.
if "%EXITCODE%"=="0" (
  echo Network return completed.
) else (
  echo Network return stopped with exit code %EXITCODE%.
)
echo.
pause
for %%# in (%EXITCODE%) do endlocal & exit /b %%#
