@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title SysAdminSuite - Northwell Printer Tools

:menu
cls
echo ================================================================
echo  NORTHWELL PRINTER TOOLS
echo ================================================================
echo  1. Map printer(s) system-wide
echo  2. Unmap printer(s) system-wide
echo  3. Undo latest observed printer state change
echo  4. Edit local printer default
echo  5. Edit batch CSV
echo  6. Run batch map/unmap plan
echo  7. Open latest printer evidence folder
echo  Q. Quit
echo.
echo  Runs from this SysAdminSuite checkout; no operator-specific path is required.
echo  Live network-device actions accept approved WAB, hardwire, or authenticated VPN authority.
echo ================================================================
set "SAS_CHOICE="
set /p "SAS_CHOICE=Choose an action: "

if /i "%SAS_CHOICE%"=="1" goto map
if /i "%SAS_CHOICE%"=="2" goto unmap
if /i "%SAS_CHOICE%"=="3" goto undo
if /i "%SAS_CHOICE%"=="4" goto defaults
if /i "%SAS_CHOICE%"=="5" goto editbatch
if /i "%SAS_CHOICE%"=="6" goto runbatch
if /i "%SAS_CHOICE%"=="7" goto evidence
if /i "%SAS_CHOICE%"=="Q" exit /b 0
if /i "%SAS_CHOICE%"=="QUIT" exit /b 0

echo.
echo Invalid choice.
pause
goto menu

:map
call "%~dp0Map-NorthwellPrinter-SystemWide.cmd"
goto menu

:unmap
call "%~dp0Unmap-NorthwellPrinter-SystemWide.cmd"
goto menu

:undo
call "%~dp0Undo-LatestNorthwellPrinterChange.cmd"
goto menu

:defaults
call "%~dp0Edit-NorthwellPrinter-Defaults.cmd"
goto menu

:editbatch
call "%~dp0Edit-NorthwellPrinter-Batch.cmd"
goto menu

:runbatch
call "%~dp0Map-NorthwellPrinters-Batch.cmd"
goto menu

:evidence
set "SAS_LATEST_POINTER=%~dp0mapping\Logs\LATEST-PATH.txt"
if not exist "%SAS_LATEST_POINTER%" (
    echo No latest printer evidence pointer exists yet.
    pause
    goto menu
)
set "SAS_LATEST_DIR="
set /p "SAS_LATEST_DIR="<"%SAS_LATEST_POINTER%"
if not defined SAS_LATEST_DIR (
    echo Latest printer evidence pointer is blank.
    pause
    goto menu
)
if not exist "%SAS_LATEST_DIR%" (
    echo Latest printer evidence directory no longer exists:
    echo   %SAS_LATEST_DIR%
    pause
    goto menu
)
start "" explorer.exe "%SAS_LATEST_DIR%"
goto menu
