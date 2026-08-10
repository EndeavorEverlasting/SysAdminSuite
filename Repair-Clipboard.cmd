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

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Repair-SasClipboard.ps1"
set "SAS_RC=%ERRORLEVEL%"

echo.
if "%SAS_RC%"=="0" (
    echo PASS: clipboard recovery and round-trip verification succeeded.
) else (
    echo FAIL: clipboard recovery did not return verification proof.
    echo Review %%LOCALAPPDATA%%\SysAdminSuite\field-runs\clipboard for evidence.
)
echo.
pause
exit /b %SAS_RC%
