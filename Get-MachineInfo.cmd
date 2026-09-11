@echo off
setlocal EnableExtensions EnableDelayedExpansion
title SysAdminSuite - Machine Information
cls

echo ================================================================
echo  SYSADMINSUITE MACHINE INFORMATION
echo ================================================================
echo  Read-only inventory: hostname, BIOS serial, IPv4, MAC, monitors.
echo  Remote inventory requires an approved protected Northwell path.
echo  Results stay on this controller under ProgramData\SysAdminSuite.
echo.
echo  Command line examples:
echo    Get-MachineInfo.cmd HOST01 HOST02
echo    Get-MachineInfo.cmd file C:\Temp\hosts.txt
echo ================================================================
echo.

set "SAS_EXIT=1"
set "SAS_MACHINEINFO_OPEN_OUTPUT=1"

if "%~1"=="" (
    set /p "SAS_MI_TARGET=Enter one computer name: "
    if not defined SAS_MI_TARGET goto usage
    call :run "!SAS_MI_TARGET!"
    goto finish
)

call :run %*
goto finish

:run
rem Installed path: trust only the installer-owned sas.cmd beside this launcher.
if exist "%~dp0sas.cmd" (
    call "%~dp0sas.cmd" machineinfo %*
    set "SAS_EXIT=!ERRORLEVEL!"
    exit /b !SAS_EXIT!
)

rem Current repository or sealed C:\SASAL path: use the sibling network-aware dispatcher.
if exist "%~dp0scripts\Invoke-SasNetworkAwareField.ps1" (
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-SasNetworkAwareField.ps1" machineinfo %*
    set "SAS_EXIT=!ERRORLEVEL!"
    exit /b !SAS_EXIT!
)

echo ERROR: No trusted SysAdminSuite machine-info runtime is beside this CMD.
echo Ask your lead to install/refresh SysAdminSuite, or run this CMD from a current SysAdminSuite folder.
set "SAS_EXIT=1"
exit /b !SAS_EXIT!

:usage
echo No target was supplied.
echo Use: Get-MachineInfo.cmd HOST01 [HOST02 ...]
echo   or Get-MachineInfo.cmd file C:\Path\hosts.txt
set "SAS_EXIT=2"

:finish
if not "!SAS_EXIT!"=="0" (
    echo.
    echo Machine inventory did not finish successfully.
    echo Keep the error and run-path evidence shown above for your lead.
    echo.
    pause
)
exit /b !SAS_EXIT!
