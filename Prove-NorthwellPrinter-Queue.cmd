@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title SysAdminSuite - Northwell Printer Operational Check

set "SAS_QUEUE="
set "SAS_PRINTER_IP="
set "SAS_TARGET="
set "SAS_EVIDENCE=%LOCALAPPDATA%\SysAdminSuite\field-runs\printer-queue-proof"

if not "%~1"=="" set "SAS_QUEUE=%~1"
if not "%~2"=="" set "SAS_PRINTER_IP=%~2"
if not "%~3"=="" set "SAS_TARGET=%~3"

if not defined SAS_QUEUE (
    echo ================================================================
    echo  NORTHWELL PRINTER OPERATIONAL CHECK - NO TEST PAGE
    echo ================================================================
    echo  Enter the canonical shared queue as \\server\queue.
    echo  This launcher does NOT print a test page.
    echo  It does NOT map the printer by IP.
    echo  Target context is recovered from the latest complete canonical mapping
    echo  evidence when that evidence identifies one unambiguous target.
    echo  If recovery is unavailable or ambiguous, enter the target PC explicitly.
    echo ================================================================
    echo.
    set /p "SAS_QUEUE=Shared printer queue: "
)

if not defined SAS_QUEUE (
    echo ERROR: shared printer queue cannot be blank.
    echo.
    set /p "SAS_DONE=Press Enter only when you are finished with this window: "
    exit /b 2
)

if not defined SAS_TARGET (
    echo.
    echo Optional: enter the mapped target PC hostname now.
    echo Press Enter to recover one unambiguous target from the latest complete mapping evidence.
    set /p "SAS_TARGET=Target PC hostname ^(recommended for multi-target batches^): "
)

if not defined SAS_PRINTER_IP (
    echo.
    echo Optional: enter the device IP only for read-only TCP 9100 evidence.
    echo Press Enter to skip. The IP is never used for mapping.
    set /p "SAS_PRINTER_IP=Printer IP ^(diagnostics only^): "
)

set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SAS_ENGINE=%~dp0scripts\Invoke-SasNorthwellPrinterQueueOperationalCheck.ps1"

if not exist "%SAS_PS%" (
    echo ERROR: Windows PowerShell 5.1 was not found.
    echo.
    set /p "SAS_DONE=Press Enter only when you are finished with this window: "
    exit /b 3
)
if not exist "%SAS_ENGINE%" (
    echo ERROR: printer operational-check engine was not found:
    echo %SAS_ENGINE%
    echo.
    set /p "SAS_DONE=Press Enter only when you are finished with this window: "
    exit /b 4
)

echo.
echo Running one bounded NO-PRINT operational check.
echo Raw diagnostics and a stable latest summary will be preserved under:
echo %SAS_EVIDENCE%
echo.

if defined SAS_TARGET (
    if defined SAS_PRINTER_IP (
        "%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_ENGINE%" -Printer "%SAS_QUEUE%" -PrinterIp "%SAS_PRINTER_IP%" -ComputerName "%SAS_TARGET%"
    ) else (
        "%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_ENGINE%" -Printer "%SAS_QUEUE%" -ComputerName "%SAS_TARGET%"
    )
) else (
    if defined SAS_PRINTER_IP (
        "%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_ENGINE%" -Printer "%SAS_QUEUE%" -PrinterIp "%SAS_PRINTER_IP%"
    ) else (
        "%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_ENGINE%" -Printer "%SAS_QUEUE%"
    )
)
set "SAS_RC=%ERRORLEVEL%"

echo.
if exist "%SAS_EVIDENCE%\latest.txt" (
    echo ================================================================
    echo  STABLE LATEST SUMMARY
    echo ================================================================
    type "%SAS_EVIDENCE%\latest.txt"
    echo ================================================================
) else (
    echo WARNING: stable latest summary was not created.
)

echo.
echo Durable evidence:
echo   %SAS_EVIDENCE%\latest.txt
echo   %SAS_EVIDENCE%\latest.json
echo   %SAS_EVIDENCE%\LATEST-PATH.txt
echo.
echo To reopen the durable evidence later, run:
echo   Open-NorthwellPrinter-Queue-Proof-Logs.cmd
echo.
echo This window will NOT close automatically.
set /p "SAS_DONE=Press Enter only when you are finished with this window: "
exit /b %SAS_RC%
