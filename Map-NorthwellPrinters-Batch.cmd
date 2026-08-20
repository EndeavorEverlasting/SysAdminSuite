@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title SysAdminSuite - Northwell Printer Batch Management

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if not "%ERRORLEVEL%"=="0" (
    echo Requesting Administrator rights required for machine-wide batch printer management...
    set "SAS_NORTHWELL_PRINTER_BATCH_LAUNCHER=%~f0"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { $p = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',('""{0}""' -f $env:SAS_NORTHWELL_PRINTER_BATCH_LAUNCHER)) -Verb RunAs -PassThru -Wait; exit $p.ExitCode } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }"
    set "SAS_ELEVATED_RC=!ERRORLEVEL!"
    exit /b !SAS_ELEVATED_RC!
)

echo ================================================================
echo  NORTHWELL REVERSIBLE PRINTER BATCH
echo ================================================================
echo  Local batch file: mapping\NorthwellPrinterBatch.csv
echo.
echo  CSV columns:
echo    Action,ComputerName,PrintServer,QueueName
echo  Action is Map or Unmap. Older local files without Action default to Map.
echo  Multiple computers/queues in one cell use semicolons.
echo.
echo  The complete plan is displayed before live work; type APPLY to execute.
echo  Only observed state transitions are written into UndoPlan.json.
echo  Undo-LatestNorthwellPrinterChange.cmd reverses those transitions.
echo  WAB, approved hardwire, and authenticated VPN routes are supported.
echo  SYSTEM-WIDE for ALL users. NO TEST PAGE.
echo ================================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mapping\Start-NorthwellPrinterBatch.ps1"
set "SAS_RC=%ERRORLEVEL%"
set "SAS_LATEST_POINTER=%~dp0mapping\Logs\LATEST-PATH.txt"
set "SAS_LATEST_DIR="

if "%SAS_RC%"=="2" (
    echo INFO: the local batch CSV was created and opened for editing.
    pause
    exit /b 2
)
if "%SAS_RC%"=="3" (
    echo CANCELLED: the displayed batch plan was not confirmed. No printer state was changed.
    pause
    exit /b 3
)
if exist "%SAS_LATEST_POINTER%" set /p "SAS_LATEST_DIR="<"%SAS_LATEST_POINTER%"

echo.
if "%SAS_RC%"=="0" (echo PASS: the batch completed with requested machine-wide state proof.) else (echo FAIL: one or more batch groups did not complete successfully.)
if defined SAS_LATEST_DIR (
    echo Evidence directory: %SAS_LATEST_DIR%
    echo Undo plan: %SAS_LATEST_DIR%\UndoPlan.json
    if exist "%SAS_LATEST_DIR%\Summary.json" start "" notepad.exe "%SAS_LATEST_DIR%\Summary.json"
)
echo.
pause
exit /b %SAS_RC%
