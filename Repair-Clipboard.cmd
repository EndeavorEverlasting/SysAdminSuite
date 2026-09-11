@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title SysAdminSuite - Clipboard Recovery

echo ================================================================
echo  SYSADMINSUITE CLIPBOARD RECOVERY
echo ================================================================
echo  Captures lightweight clipboard evidence, restarts the current
echo  user's Clipboard User Service, clears the clipboard, and proves
echo  copy/paste with a round-trip test.
echo ================================================================
echo.

set "SAS_PS="
where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    set "SAS_PS=pwsh"
) else (
    where powershell.exe >nul 2>nul
    if %ERRORLEVEL% EQU 0 set "SAS_PS=powershell.exe"
)

if not defined SAS_PS (
    echo FAIL: neither PowerShell 7 nor Windows PowerShell is available on PATH.
    exit /b 2
)

"%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Repair-SasClipboard.ps1"
set "SAS_RC=%ERRORLEVEL%"

echo.
if "%SAS_RC%"=="0" (
    echo PASS: clipboard recovery and round-trip verification succeeded.
) else (
    echo FAIL: clipboard recovery did not return complete verification proof.
    echo Review %%LOCALAPPDATA%%\SysAdminSuite\field-runs\clipboard for evidence.
)
echo.
pause
exit /b %SAS_RC%
