@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
title SysAdminSuite - Install Universal Field Command

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Install-SasUniversalFieldLauncher.ps1"
set "EXITCODE=%ERRORLEVEL%"

echo.
if "%EXITCODE%"=="0" (
  echo Installation completed. Open a NEW terminal and run: sas platform
  echo The same sas command supports Northwell hardwire, NSLIJHS-WAB, and authenticated VPN paths.
) else (
  echo Installation stopped with exit code %EXITCODE%.
)
echo.
pause
endlocal & exit /b %EXITCODE%
