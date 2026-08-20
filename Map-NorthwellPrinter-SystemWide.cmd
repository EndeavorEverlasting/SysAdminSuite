@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title SysAdminSuite - Northwell Quick Printer Mapping

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if not "%ERRORLEVEL%"=="0" (
    echo Requesting Administrator rights required for machine-wide mapping...
    set "SAS_NORTHWELL_PRINTER_LAUNCHER=%~f0"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { $p = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',('""{0}""' -f $env:SAS_NORTHWELL_PRINTER_LAUNCHER)) -Verb RunAs -PassThru -Wait; exit $p.ExitCode } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }"
    set "SAS_ELEVATED_RC=!ERRORLEVEL!"
    exit /b !SAS_ELEVATED_RC!
)

echo ================================================================
echo  NORTHWELL QUICK SYSTEM-WIDE PRINTER MAPPING
echo ================================================================
echo  Enter one or more target PC hostnames and shared printer queues.
echo  Accepted printer input: \\server\queue, //server/queue, or server + queue prompts.
echo.
echo  Supported controller networks:
echo    - Northwell WAB Wi-Fi
echo    - approved DomainAuthenticated hardwire/LAN
echo    - authenticated VPN / protected non-Wi-Fi route
echo.
echo  Optional convenience: Edit-NorthwellPrinter-Defaults.cmd
echo  stores one approved server/queue pair in a LOCAL gitignored file.
echo.
echo  Mapping is SYSTEM-WIDE for ALL users and uses PrintUIEntry /ga.
echo  Already-present queues are a safe NOOP.
echo  Only actual state transitions appear in UndoPlan.json.
echo  Undo-LatestNorthwellPrinterChange.cmd reverses those transitions.
echo  NO TEST PAGE is printed.
echo ================================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mapping\Start-NorthwellPrinterMapping.ps1" -Action Map
set "SAS_RC=%ERRORLEVEL%"
set "SAS_LATEST_POINTER=%~dp0mapping\Logs\LATEST-PATH.txt"
set "SAS_LATEST_DIR="
if exist "%SAS_LATEST_POINTER%" set /p "SAS_LATEST_DIR="<"%SAS_LATEST_POINTER%"

echo.
if "%SAS_RC%"=="0" (echo PASS: requested machine-wide printer state is present.) else (echo FAIL: mapping did not complete with machine-wide presence proof.)
if defined SAS_LATEST_DIR (
    echo.
    echo Evidence directory:
    echo   %SAS_LATEST_DIR%
    echo Primary artifacts:
    echo   %SAS_LATEST_DIR%\ResolvedPlan.json
    echo   %SAS_LATEST_DIR%\Controller.log
    echo   %SAS_LATEST_DIR%\Summary.json
    echo   %SAS_LATEST_DIR%\UndoPlan.json
    echo   %SAS_LATEST_DIR%\^<target^>\Status.json
    echo   %SAS_LATEST_DIR%\^<target^>\Agent.log
    if exist "%SAS_LATEST_DIR%\Summary.json" start "" notepad.exe "%SAS_LATEST_DIR%\Summary.json"
)
echo.
echo This window will stay open until you close it or press a key.
pause
exit /b %SAS_RC%
