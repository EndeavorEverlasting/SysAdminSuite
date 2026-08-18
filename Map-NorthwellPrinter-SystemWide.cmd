@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title SysAdminSuite - Northwell System-Wide Printer Mapping

rem Canonical Northwell multi-user printer front door.
rem Mapping remains shared-queue-only and machine-wide through SYSTEM + PrintUIEntry /ga.
rem If an exact same-queue local printer object is bound to a direct-IP port, the
rem delegated engine may remove that stale printer OBJECT before /ga. It never
rem deletes the TCP/IP port and never prints a test page.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if not "%ERRORLEVEL%"=="0" (
    echo Requesting Administrator rights required for machine-wide mapping...
    set "SAS_NORTHWELL_PRINTER_LAUNCHER=%~f0"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { $p = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',('""{0}""' -f $env:SAS_NORTHWELL_PRINTER_LAUNCHER)) -Verb RunAs -PassThru -Wait; exit $p.ExitCode } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }"
    exit /b %ERRORLEVEL%
)

echo ================================================================
echo  NORTHWELL SYSTEM-WIDE PRINTER MAPPING
echo ================================================================
echo  Use target PC HOSTNAMES and printer QUEUE NAMES only.
echo  Accepted printer input: \server\queue, //server/queue, or queue name.
echo  Printer IP addresses are NOT allowed as mapping targets.
echo  Mapping is per-computer for ALL users, not just the signed-in user.
echo.
echo  Repair behavior:
echo    - exact same-queue local direct-IP printer OBJECT may be removed
echo    - its TCP/IP PORT is preserved
echo    - ambiguous collisions fail closed
echo    - NO TEST PAGE is printed
echo ================================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mapping\Start-NorthwellPrinterMapping.ps1"
set "SAS_RC=%ERRORLEVEL%"
set "SAS_LATEST_POINTER=%~dp0mapping\Logs\LATEST-PATH.txt"
set "SAS_LATEST_DIR="

if exist "%SAS_LATEST_POINTER%" (
    set /p "SAS_LATEST_DIR="<"%SAS_LATEST_POINTER%"
)

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
    if exist "%SAS_LATEST_DIR%\Summary.json" (
        start "" notepad.exe "%SAS_LATEST_DIR%\Summary.json"
    )
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
