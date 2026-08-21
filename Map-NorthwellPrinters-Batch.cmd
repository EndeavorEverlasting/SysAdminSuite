@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title SysAdminSuite - Northwell Printer Batch Management
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

"%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if not "%ERRORLEVEL%"=="0" (
    echo Requesting Administrator rights required for machine-wide batch printer management...
    set "SAS_NORTHWELL_PRINTER_BATCH_LAUNCHER=%~f0"
    "%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -Command "try { $p = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',('""{0}""' -f $env:SAS_NORTHWELL_PRINTER_BATCH_LAUNCHER)) -Verb RunAs -PassThru -Wait; exit $p.ExitCode } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }"
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
echo  Successful Map rows are then made available to users already logged on.
echo  Unmap rows are never sent through the active-user mapping finalizer.
echo  SYSTEM-WIDE for ALL users. NO TEST PAGE.
echo ================================================================
echo.

"%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0mapping\Start-NorthwellPrinterBatch.ps1"
set "SAS_RC=%ERRORLEVEL%"
set "SAS_LATEST_POINTER=%~dp0mapping\Logs\LATEST-PATH.txt"
set "SAS_LATEST_DIR="

if "%SAS_RC%"=="2" (
    echo.
    echo INFO: the local batch CSV was created and opened for editing.
    echo Save it, then run this CMD again.
    echo.
    pause
    exit /b 2
)
if "%SAS_RC%"=="3" (
    echo.
    echo CANCELLED: the displayed batch plan was not confirmed. No printer state was changed.
    echo.
    pause
    exit /b 3
)

if exist "%SAS_LATEST_POINTER%" set /p "SAS_LATEST_DIR="<"%SAS_LATEST_POINTER%"

if "%SAS_RC%"=="0" (
    echo.
    echo Finalizing active-user availability for successful Map rows only...
    "%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0mapping\Confirm-NorthwellPrinterBatchActiveUserMaterialization.ps1"
    set "SAS_RC=!ERRORLEVEL!"
)

echo.
if "%SAS_RC%"=="0" (
    echo PASS: requested machine-wide printer state is proven; active Map rows were finalized for current users.
) else (
    echo FAIL: printer mapping is not complete for one or more current sessions or a requested batch state failed.
)

if defined SAS_LATEST_DIR (
    echo.
    echo Evidence directory:
    echo   %SAS_LATEST_DIR%
    echo.
    echo Primary batch artifacts:
    echo   %SAS_LATEST_DIR%\BatchPlan.json
    echo   %SAS_LATEST_DIR%\Summary.json
    echo   %SAS_LATEST_DIR%\UndoPlan.json
    echo   %SAS_LATEST_DIR%\ActiveUserMaterialization.json
    if exist "%SAS_LATEST_DIR%\Summary.json" start "" notepad.exe "%SAS_LATEST_DIR%\Summary.json"
)

echo.
echo This window will stay open until you close it or press a key.
pause
exit /b %SAS_RC%
