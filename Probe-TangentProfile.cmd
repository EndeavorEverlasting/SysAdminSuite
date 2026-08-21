@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
title SysAdminSuite - Tangent Read-Only Hardware Profile

if /I "%~1"=="Help" goto help_ok
if /I "%~1"=="-h" goto help_ok
if /I "%~1"=="--help" goto help_ok
if /I "%~1"=="/?" goto help_ok
if /I not "%~1"=="Probe" goto help_error
shift
if "%~1"=="" goto help_error

echo.
echo Read-only Tangent candidate hardware profile collection.
echo No software install, configuration change, task creation, registry write, or restart will occur.
echo A Tangent label is candidate context only; hardware classification requires observed model + serial evidence.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Invoke-SasReadOnlyWorkstationProfileProbe.ps1" -CandidateLabel "TangentCandidate" -ComputerName %*
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Tangent profile probe stopped with exit code %EXITCODE%. Review the local comparison evidence before retrying.
endlocal & exit /b %EXITCODE%

:help_ok
call :print_help
exit /b 0

:help_error
call :print_help
exit /b 2

:print_help
echo SysAdminSuite Tangent Read-Only Hardware Profile Probe
echo.
echo Usage:
echo   Probe-TangentProfile.cmd Probe HOST01 [HOST02 ...]
echo.
echo Collects comparison-ready manufacturer/model/product/BIOS serial/board/OS/CPU/RAM/COM/MAC evidence.
echo Run the generic PowerShell probe against a separately proven Cybernet reference host to compare rows.
echo Live evidence remains local under survey\output\workstation_profile_probe and must not be committed.
goto :eof
