@echo off
setlocal EnableExtensions
title SysAdminSuite - H^&H CC Reader Admin Box ADB Host Prepare

if /I "%~1"=="/?" goto usage
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage

if not exist "%~dp0harness\api\hh_cc_reader_adb_control_plane.py" (
  echo ERROR: ADB control-plane classifier is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER ADMIN BOX ADB HOST PREPARE
echo ================================================================
echo  Install or locate official Google Android Platform-Tools.
echo  Uses a SysAdminSuite-owned local cache. Does not require Android Studio.
echo  Never mutates the payment terminal.
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
%PYEXE% "%~dp0harness\api\hh_cc_reader_adb_control_plane.py" --live prepare-host --allow-install %*
exit /b %ERRORLEVEL%

:fixture
%PYEXE% "%~dp0harness\api\hh_cc_reader_adb_control_plane.py" --input "%~2"
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   Prepare-HHCCReaderAdbHost.cmd
echo   Prepare-HHCCReaderAdbHost.cmd --fixture EVIDENCE.json
exit /b 2
