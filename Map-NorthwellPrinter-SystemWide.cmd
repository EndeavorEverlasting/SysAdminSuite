@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title SysAdminSuite - Northwell Quick Printer Mapping

rem Canonical Northwell quick technician front door.
rem Mapping remains shared-queue-only and machine-wide through SYSTEM + PrintUIEntry /ga.
rem This launcher does not remove printers or ports and never prints a test page.

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
echo  1. Enter one or more target PC HOSTNAMES.
echo  2. Enter a print SERVER and one or more QUEUE NAMES.
echo  3. Add another server/queue set if needed.
echo.
echo  Accepted printer input: \\server\queue, //server/queue, or server + queue prompts.
echo.
echo  Optional convenience:
echo    Edit-NorthwellPrinter-Defaults.cmd
echo  stores one approved server/queue pair in a LOCAL gitignored file.
echo  When configured, press Enter at the bracketed prompts to accept it.
echo.
echo  Printer IP addresses are NOT allowed as mapping targets.
echo  Mapping is per-computer for ALL users, not just the signed-in user.
echo  NO TEST PAGE is printed.
echo.
echo  For spreadsheet-style batches, use:
echo    Edit-NorthwellPrinter-Batch.cmd
echo    Map-NorthwellPrinters-Batch.cmd
echo ================================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mapping\Start-NorthwellPrinterMapping.ps1"
set "SAS_RC=%ERRORLEVEL%"
set "SAS_LATEST_POINTER=%~dp0mapping\Logs\LATEST-PATH.txt"
set "SAS_LATEST_DIR="

if exist "%SAS_LATEST_POINTER%" set /p "SAS_LATEST_DIR="<"%SAS_LATEST_POINTER%"

echo.
if "%SAS_RC%"=="0" (
    echo PASS: the requested target(s) returned machine-wide printer proof.
) else (
    echo FAIL: printer mapping did not complete with machine-wide proof.
)

if defined SAS_LATEST_DIR (
    echo.
    echo Evidence directory:
    echo   %SAS_LATEST_DIR%
    echo.
    echo Primary artifacts:
    echo   %SAS_LATEST_DIR%\ResolvedPlan.json
    echo   %SAS_LATEST_DIR%\Controller.log
    echo   %SAS_LATEST_DIR%\Summary.json
    echo   %SAS_LATEST_DIR%\^<target^>\Status.json
    echo   %SAS_LATEST_DIR%\^<target^>\Agent.log
    if exist "%SAS_LATEST_DIR%\Summary.json" start "" notepad.exe "%SAS_LATEST_DIR%\Summary.json"
) else (
    echo.
    echo No mapping evidence pointer was found.
    echo Expected pointer: %SAS_LATEST_POINTER%
    echo Review mapping\Logs\NorthwellPrinterMap-* if the engine failed before writing it.
)

echo.
echo This window will stay open until you close it or press a key.
pause
exit /b %SAS_RC%
