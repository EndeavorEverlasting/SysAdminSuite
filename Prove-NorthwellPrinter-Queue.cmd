@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title SysAdminSuite - Northwell Printer Queue Proof

set "SAS_QUEUE="
set "SAS_PRINTER_IP="
set "SAS_PRINT_TEST="

if not "%~1"=="" set "SAS_QUEUE=%~1"
if not "%~2"=="" set "SAS_PRINTER_IP=%~2"

if not defined SAS_QUEUE (
    echo ================================================================
    echo  NORTHWELL PRINTER QUEUE PROOF
    echo ================================================================
    echo  Enter the canonical shared queue as \server\queue.
    echo  Do not paste a PowerShell prompt, terminal transcript, or printer IP.
    echo ================================================================
    echo.
    set /p "SAS_QUEUE=Shared printer queue: "
)

if not defined SAS_QUEUE (
    echo ERROR: shared printer queue cannot be blank.
    pause
    exit /b 2
)

if not defined SAS_PRINTER_IP (
    echo.
    echo Optional: enter the device IP only for diagnostic TCP 9100 evidence.
    echo Press Enter to skip. The IP is never used for mapping.
    set /p "SAS_PRINTER_IP=Printer IP ^(diagnostics only^): "
)

echo.
set /p "SAS_PRINT_TEST=Issue one bounded Windows test page? [y/N]: "

set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SAS_ENGINE=%~dp0scripts\Invoke-SasNorthwellPrinterQueueProof.ps1"

if not exist "%SAS_PS%" (
    echo ERROR: Windows PowerShell 5.1 was not found.
    pause
    exit /b 3
)
if not exist "%SAS_ENGINE%" (
    echo ERROR: printer queue proof engine was not found:
    echo %SAS_ENGINE%
    pause
    exit /b 4
)

set "SAS_TEST_SWITCH="
if /I "%SAS_PRINT_TEST%"=="Y" set "SAS_TEST_SWITCH=-PrintTestPage"
if /I "%SAS_PRINT_TEST%"=="YES" set "SAS_TEST_SWITCH=-PrintTestPage"

echo.
echo Running one bounded proof transaction. No direct-IP printer mapping will occur.
echo.

if defined SAS_PRINTER_IP (
    "%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_ENGINE%" -Printer "%SAS_QUEUE%" -PrinterIp "%SAS_PRINTER_IP%" %SAS_TEST_SWITCH%
) else (
    "%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_ENGINE%" -Printer "%SAS_QUEUE%" %SAS_TEST_SWITCH%
)
set "SAS_RC=%ERRORLEVEL%"

echo.
if "%SAS_RC%"=="0" (
    echo PASS/PARTIAL: proof engine completed without a classified failure.
) else (
    echo FAIL: proof engine preserved a classified failure artifact.
)
echo Evidence lives under %%LOCALAPPDATA%%\SysAdminSuite\field-runs\printer-queue-proof\
echo.
pause
exit /b %SAS_RC%
