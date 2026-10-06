@echo off
setlocal EnableExtensions
title SysAdminSuite - H^&H CC Reader Admin Box ADB Probe

if /I "%~1"=="/?" goto usage
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage

if not exist "%~dp0harness\api\hh_cc_reader_adb_control_plane.py" (
  echo ERROR: ADB control-plane classifier is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER ADMIN BOX ADB PROBE
echo ================================================================
echo  Classify Admin Box ADB-host readiness and Kiosk4 USB/ADB session.
echo  Unauthorized is a proved transport state, not a generic failure.
echo  Never mutates firmware, apps, or payment configuration.
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
%PYEXE% "%~dp0harness\api\hh_cc_reader_adb_control_plane.py" --live probe %*
exit /b %ERRORLEVEL%

:fixture
%PYEXE% "%~dp0harness\api\hh_cc_reader_adb_control_plane.py" --input "%~2"
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   Probe-HHCCReaderAdb.cmd
echo   Probe-HHCCReaderAdb.cmd --expected-mac AA-BB-CC-DD-EE-FF
echo   Probe-HHCCReaderAdb.cmd --fixture EVIDENCE.json
exit /b 2
