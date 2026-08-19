@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title SysAdminSuite - Edit Northwell Printer Batch

set "SAS_BATCH_FILE=%~dp0mapping\NorthwellPrinterBatch.csv"
set "SAS_BATCH_EXAMPLE=%~dp0mapping\Examples\NorthwellPrinterBatch.example.csv"

if not exist "%SAS_BATCH_EXAMPLE%" (
    echo ERROR: tracked batch example is missing:
    echo   %SAS_BATCH_EXAMPLE%
    pause
    exit /b 1
)

if not exist "%SAS_BATCH_FILE%" (
    copy /y "%SAS_BATCH_EXAMPLE%" "%SAS_BATCH_FILE%" >nul
    if errorlevel 1 (
        echo ERROR: could not create local batch file:
        echo   %SAS_BATCH_FILE%
        pause
        exit /b 1
    )
    echo Created local batch file from the tracked example.
)

echo.
echo Edit this local, gitignored file:
echo   %SAS_BATCH_FILE%
echo.
echo Columns: ComputerName,PrintServer,QueueName
echo Use semicolons inside a cell for multiple computers or queues.
echo Example: PC001;PC002,SYKPNHPHPS01V,LS001-EMS01;QUEUE02
echo.
echo Save the file, then double-click Map-NorthwellPrinters-Batch.cmd.
echo.
start "" notepad.exe "%SAS_BATCH_FILE%"
pause
exit /b 0
