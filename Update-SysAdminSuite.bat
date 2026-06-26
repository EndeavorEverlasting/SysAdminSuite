@echo off
setlocal
title SysAdminSuite Update

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-SysAdminSuite.ps1"
set "RC=%errorlevel%"

echo.
echo Press any key to close...
pause >nul
exit /b %RC%
