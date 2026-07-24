@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
title SysAdminSuite - AutoLogon On-Site

if not "%~3"=="" (
  echo ERROR: This launcher accepts ACTION and optional TARGET only.
  echo Examples:
  echo   Run-AutoLogonOnsite.cmd Prepare
  echo   Run-AutoLogonOnsite.cmd Remote HOST
  exit /b 2
)

if "%~1"=="" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Invoke-SasAutoLogonOnsite.ps1" -Action Menu
) else if "%~2"=="" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Invoke-SasAutoLogonOnsite.ps1" -Action "%~1"
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Invoke-SasAutoLogonOnsite.ps1" -Action "%~1" -ComputerName "%~2"
)
set "EXITCODE=%ERRORLEVEL%"

if not "%EXITCODE%"=="0" (
  echo.
  echo AutoLogon on-site workflow stopped with exit code %EXITCODE%.
)

endlocal & exit /b %EXITCODE%
