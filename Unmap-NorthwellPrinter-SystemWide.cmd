@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title SysAdminSuite - Northwell Quick Printer Unmapping

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if not "%ERRORLEVEL%"=="0" (
    echo Requesting Administrator rights required for machine-wide unmapping...
    set "SAS_NORTHWELL_PRINTER_LAUNCHER=%~f0"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { $p = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',('""{0}""' -f $env:SAS_NORTHWELL_PRINTER_LAUNCHER)) -Verb RunAs -PassThru -Wait; exit $p.ExitCode } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }"
    set "SAS_ELEVATED_RC=!ERRORLEVEL!"
    exit /b !SAS_ELEVATED_RC!
)

echo ================================================================
echo  NORTHWELL QUICK SYSTEM-WIDE PRINTER UNMAPPING
echo ================================================================
echo  Removes only the requested per-computer shared queue registration.
echo  Uses the paired PrintUIEntry /gd path; no printer port is deleted.
echo  Already-absent queues are a safe NOOP.
echo.
echo  Supported controller networks:
echo    - Northwell WAB Wi-Fi
echo    - approved DomainAuthenticated hardwire/LAN
echo    - authenticated VPN / protected non-Wi-Fi route
echo.
echo  A successful state transition is recorded in UndoPlan.json.
echo  Undo-LatestNorthwellPrinterChange.cmd can restore it.
echo  NO TEST PAGE is printed.
echo ================================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mapping\Start-NorthwellPrinterMapping.ps1" -Action Unmap
set "SAS_RC=%ERRORLEVEL%"
set "SAS_LATEST_POINTER=%~dp0mapping\Logs\LATEST-PATH.txt"
set "SAS_LATEST_DIR="
if exist "%SAS_LATEST_POINTER%" set /p "SAS_LATEST_DIR="<"%SAS_LATEST_POINTER%"

echo.
if "%SAS_RC%"=="0" (echo PASS: requested machine-wide printer state is absent.) else (echo FAIL: unmapping did not complete with machine-wide absence proof.)
if defined SAS_LATEST_DIR (
    echo Evidence directory: %SAS_LATEST_DIR%
    echo Undo plan: %SAS_LATEST_DIR%\UndoPlan.json
    if exist "%SAS_LATEST_DIR%\Summary.json" start "" notepad.exe "%SAS_LATEST_DIR%\Summary.json"
)
echo.
echo This window will stay open until you close it or press a key.
pause
exit /b %SAS_RC%
