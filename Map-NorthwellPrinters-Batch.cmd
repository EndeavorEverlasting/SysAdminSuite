@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title SysAdminSuite - Northwell Printer Batch Mapping

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if not "%ERRORLEVEL%"=="0" (
    echo Requesting Administrator rights required for machine-wide batch mapping...
    set "SAS_NORTHWELL_PRINTER_BATCH_LAUNCHER=%~f0"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { $p = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',('""{0}""' -f $env:SAS_NORTHWELL_PRINTER_BATCH_LAUNCHER)) -Verb RunAs -PassThru -Wait; exit $p.ExitCode } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }"
    set "SAS_ELEVATED_RC=!ERRORLEVEL!"
    exit /b !SAS_ELEVATED_RC!
)

echo ================================================================
echo  NORTHWELL PRINTER BATCH MAPPING
echo ================================================================
echo  Local batch file:
echo    mapping\NorthwellPrinterBatch.csv
echo.
echo  CSV columns:
echo    ComputerName,PrintServer,QueueName
echo.
echo  Put multiple computers or queues in ONE cell with semicolons.
echo  Example using synthetic names:
echo    PC001;PC002,PRINTSERVER01,QUEUE01;QUEUE02
echo.
echo  Each row maps every listed queue to every listed computer in that row.
echo  You will see the resolved plan and must type MAP before live mutation.
echo  Phase 1 registers SYSTEM-wide for all users.
echo  Phase 2 immediately connects and verifies any user already logged on.
echo  NO TEST PAGE is printed.
echo ================================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mapping\Start-NorthwellPrinterBatch.ps1"
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
    echo CANCELLED: the displayed batch plan was not confirmed. No mapping was performed.
    echo.
    pause
    exit /b 3
)

if exist "%SAS_LATEST_POINTER%" set /p "SAS_LATEST_DIR="<"%SAS_LATEST_POINTER%"

if "%SAS_RC%"=="0" (
    echo.
    echo Verifying immediate availability for any users already logged on...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mapping\Confirm-NorthwellPrinterActiveUserMaterialization.ps1"
    set "SAS_RC=!ERRORLEVEL!"
)

echo.
if "%SAS_RC%"=="0" (
    echo PASS: machine-wide registration is proven and every active user session was finalized successfully.
) else (
    echo FAIL: printer mapping is not complete for one or more current sessions.
)

if defined SAS_LATEST_DIR (
    echo.
    echo Evidence directory:
    echo   %SAS_LATEST_DIR%
    echo.
    echo Primary batch artifacts:
    echo   %SAS_LATEST_DIR%\BatchPlan.json
    echo   %SAS_LATEST_DIR%\Summary.json
    echo   %SAS_LATEST_DIR%\ActiveUserMaterialization.json
    echo   %SAS_LATEST_DIR%\Group-001\Summary.json
    if exist "%SAS_LATEST_DIR%\Summary.json" start "" notepad.exe "%SAS_LATEST_DIR%\Summary.json"
)

echo.
echo This window will stay open until you close it or press a key.
pause
exit /b %SAS_RC%
