@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title SysAdminSuite - Northwell Printer Mapping
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

rem Low-noise Northwell quick mapper.
rem No ping sweep, no test page, no per-user fallback.
rem The PowerShell front-end reports only the authoritative HKLM result and evidence path.

"%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if not "%ERRORLEVEL%"=="0" (
    echo Requesting Administrator rights...
    set "SAS_NORTHWELL_PRINTER_LAUNCHER=%~f0"
    "%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -Command "try { $p = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',('""{0}""' -f $env:SAS_NORTHWELL_PRINTER_LAUNCHER)) -Verb RunAs -PassThru -Wait; exit $p.ExitCode } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }"
    set "SAS_ELEVATED_RC=!ERRORLEVEL!"
    exit /b !SAS_ELEVATED_RC!
)

echo Northwell system-wide printer mapping
"%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0mapping\Start-NorthwellPrinterMapping.ps1"
set "SAS_RC=%ERRORLEVEL%"

echo.
if "%SAS_RC%"=="0" (
    echo Done.
) else (
    echo Mapping was not proven. Use the evidence path printed above; do not remap blindly.
)
echo.
pause
exit /b %SAS_RC%
