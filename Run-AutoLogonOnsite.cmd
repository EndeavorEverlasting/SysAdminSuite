@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
title SysAdminSuite - AutoLogon On-Site Qualification

if not "%~2"=="" (
  echo ERROR: This launcher accepts at most one optional action: Prepare, Validate, Pilot, or Evidence.
  exit /b 2
)

if "%~1"=="" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Invoke-SasAutoLogonOnsite.ps1" -Action Menu
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Invoke-SasAutoLogonOnsite.ps1" -Action "%~1"
)
set "EXITCODE=%ERRORLEVEL%"

if not "%EXITCODE%"=="0" (
  echo.
  echo AutoLogon on-site workflow stopped with exit code %EXITCODE%.
)

endlocal & exit /b %EXITCODE%
