@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title SysAdminSuite - Edit Northwell Printer Defaults

set "SAS_DEFAULT_FILE=%~dp0Config\northwell-printer-defaults.local.json"
set "SAS_DEFAULT_EXAMPLE=%~dp0mapping\Examples\NorthwellPrinterDefaults.example.json"

if not exist "%SAS_DEFAULT_EXAMPLE%" (
    echo ERROR: tracked synthetic defaults example is missing:
    echo   %SAS_DEFAULT_EXAMPLE%
    pause
    exit /b 1
)

if not exist "%~dp0Config" mkdir "%~dp0Config"
if not exist "%SAS_DEFAULT_FILE%" (
    copy /y "%SAS_DEFAULT_EXAMPLE%" "%SAS_DEFAULT_FILE%" >nul
    if errorlevel 1 (
        echo ERROR: could not create local defaults file:
        echo   %SAS_DEFAULT_FILE%
        pause
        exit /b 1
    )
)

echo.
echo Edit this LOCAL, gitignored file:
echo   %SAS_DEFAULT_FILE%
echo.
echo Replace both REPLACE-WITH-* values with one approved Northwell
echo print server and queue. The quick mapping CMD will then show those
echo values in brackets and pressing Enter will explicitly accept them.
echo.
echo This editor does not map a printer.
echo.
start "" notepad.exe "%SAS_DEFAULT_FILE%"
pause
exit /b 0
