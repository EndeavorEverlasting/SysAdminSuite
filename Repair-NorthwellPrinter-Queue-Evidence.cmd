@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title SysAdminSuite - Repair Northwell Printer Evidence

set "SAS_QUEUE=%~1"
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SAS_ENGINE=%~dp0scripts\Repair-SasNorthwellPrinterQueueEvidence.ps1"
set "SAS_EVIDENCE=%LOCALAPPDATA%\SysAdminSuite\field-runs\printer-queue-proof"

if not exist "%SAS_PS%" (
    echo ERROR: Windows PowerShell 5.1 was not found.
    pause
    exit /b 3
)
if not exist "%SAS_ENGINE%" (
    echo ERROR: evidence repair engine was not found:
    echo %SAS_ENGINE%
    pause
    exit /b 4
)

echo ================================================================
echo  REPAIR EXISTING PRINTER EVIDENCE - NO PRINT / NO NETWORK
echo  ARTIFACT RECLASSIFICATION ONLY
echo ================================================================
echo  Use only when preserved local JSON already records physical output
echo  and the derived classifier needs repair.
echo.
echo  This launcher is NOT required after a successful real document print.
echo  A working mapped printer does not need another proof or repair step.
echo.
echo  This reads existing local JSON evidence only.
echo  It never contacts the printer or print server.
echo  It never prints a test page.
echo ================================================================
echo.

if defined SAS_QUEUE (
    "%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_ENGINE%" -Printer "%SAS_QUEUE%"
) else (
    "%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_ENGINE%"
)
set "SAS_RC=%ERRORLEVEL%"

echo.
if exist "%SAS_EVIDENCE%\latest.txt" type "%SAS_EVIDENCE%\latest.txt"
echo.
echo Durable result: %SAS_EVIDENCE%\latest.json
echo Durable summary: %SAS_EVIDENCE%\latest.txt
echo.
echo This window will NOT close automatically.
set /p "SAS_DONE=Press Enter only when you are finished with this window: "
exit /b %SAS_RC%
