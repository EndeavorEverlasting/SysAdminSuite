@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
title SysAdminSuite - Install Portable Operator Command

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Install-SasPortableLauncher.ps1"
set "EXITCODE=%ERRORLEVEL%"

echo.
if "%EXITCODE%"=="0" (
  echo Installation completed. Open a NEW terminal and run: sas
) else (
  echo Installation stopped with exit code %EXITCODE%.
)
echo.
pause
endlocal & exit /b %EXITCODE%
