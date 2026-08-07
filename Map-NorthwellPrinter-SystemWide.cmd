@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title SysAdminSuite - Northwell System-Wide Printer Mapping

rem This is the Northwell multi-user printer front door.
rem The delegated PowerShell engine rejects IP-based printer mapping and proves
rem the requested shared queue under HKLM after running PrintUIEntry /ga as SYSTEM.

net session >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
    echo Requesting Administrator rights required for machine-wide mapping...
    set "SAS_NORTHWELL_PRINTER_LAUNCHER=%~f0"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { $p = Start-Process -FilePath $env:SAS_NORTHWELL_PRINTER_LAUNCHER -Verb RunAs -PassThru -Wait; exit $p.ExitCode } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }"
    exit /b %ERRORLEVEL%
)

echo ================================================================
echo  NORTHWELL SYSTEM-WIDE PRINTER MAPPING
echo ================================================================
echo  Use target PC HOSTNAMES and printer QUEUE NAMES only.
echo  Accepted printer input: \server\queue, //server/queue, or queue name.
echo  Printer IP addresses are NOT allowed.
echo  Mapping is per-computer for ALL users, not just the signed-in user.
echo ================================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mapping\Start-NorthwellPrinterMapping.ps1"
set "SAS_RC=%ERRORLEVEL%"

echo.
if "%SAS_RC%"=="0" (
    echo PASS: the requested target(s) returned machine-wide printer proof.
) else (
    echo FAIL: printer mapping did not complete with machine-wide proof.
    echo Review mapping\Logs\NorthwellPrinterMap-* for ResolvedPlan.json,
    echo Controller.log, per-target Status.json / Agent.log, and Summary.json.
)
echo.
pause
exit /b %SAS_RC%
