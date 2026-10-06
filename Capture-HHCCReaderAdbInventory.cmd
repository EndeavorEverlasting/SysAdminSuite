@echo off
setlocal EnableExtensions
title SysAdminSuite - H^&H CC Reader Admin Box ADB Inventory

if /I "%~1"=="/?" goto usage
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage

if not exist "%~dp0harness\api\hh_cc_reader_adb_control_plane.py" (
  echo ERROR: ADB control-plane classifier is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER ADMIN BOX ADB READ-ONLY INVENTORY
echo ================================================================
echo  Capture getprop/packages/process/network/policy metadata only.
echo  Adapts version properties into Classify-HHCCReaderVersionDomain.
echo  Never treats campaign 2.0.15.260522 as observed current firmware.
echo ================================================================
echo.

cd /d "%~dp0"
set "PYEXE="
where py >nul 2>&1 && set "PYEXE=py -3"
if not defined PYEXE where python >nul 2>&1 && set "PYEXE=python"
if not defined PYEXE (
  echo ERROR: Python 3 is required ^(py -3 or python on PATH^).
  exit /b 1
)

if /I "%~1"=="-Fixture" goto fixture
if /I "%~1"=="--fixture" goto fixture
%PYEXE% "%~dp0harness\api\hh_cc_reader_adb_control_plane.py" --live inventory %*
exit /b %ERRORLEVEL%

:fixture
%PYEXE% "%~dp0harness\api\hh_cc_reader_adb_control_plane.py" --input "%~2"
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   Capture-HHCCReaderAdbInventory.cmd
echo   Capture-HHCCReaderAdbInventory.cmd --expected-mac AA-BB-CC-DD-EE-FF
echo   Capture-HHCCReaderAdbInventory.cmd --fixture EVIDENCE.json
exit /b 2
