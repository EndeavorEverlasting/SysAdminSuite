@echo off
setlocal EnableExtensions EnableDelayedExpansion
title SysAdminSuite - Northwell Printer Mapper
cls

echo ================================================================
echo  NORTHWELL PRINTER MAPPER
echo ================================================================
echo  Maps approved Northwell shared printer queues to one or more PCs.
echo  The mapping is SYSTEM-wide for all users. No test page is printed.
echo.
echo  Before you begin: connect to Northwell hardwire, WAB, or an
echo  authenticated Northwell VPN. Approve the Administrator prompt if shown.
echo.
echo  Tip: Recent proven PCs and printers are remembered. On repeat jobs,
echo  choose the displayed number instead of retyping the hostname or printer path.
echo ================================================================
echo.

set "SAS_EXIT=1"

rem Installed path: trust only the installer-owned sas.cmd beside this launcher.
if exist "%~dp0sas.cmd" (
    call "%~dp0sas.cmd" printer
    set "SAS_EXIT=!ERRORLEVEL!"
    goto finish
)

rem Current repository/runtime path: use only a sibling trusted printer bootstrap.
if exist "%~dp0Bootstrap-SysAdminSuitePrinter.cmd" (
    call "%~dp0Bootstrap-SysAdminSuitePrinter.cmd"
    set "SAS_EXIT=!ERRORLEVEL!"
    goto finish
)

if exist "%~dp0Bootstrap-SysAdminSuitePrinter.ps1" (
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Bootstrap-SysAdminSuitePrinter.ps1"
    set "SAS_EXIT=!ERRORLEVEL!"
    goto finish
)

echo ERROR: No trusted SysAdminSuite printer runtime is beside this CMD.
echo Ask your lead to install/refresh SysAdminSuite, or run this CMD from a current SysAdminSuite folder.
set "SAS_EXIT=1"

:finish
if not "!SAS_EXIT!"=="0" (
    echo.
    echo Printer mapping did not finish successfully.
    echo Do not keep remapping blindly. Keep the error/evidence shown above for your lead.
    echo.
    pause
)
exit /b !SAS_EXIT!
