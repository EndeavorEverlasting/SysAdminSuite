@echo off
setlocal EnableExtensions
title SysAdminSuite - H^&H CC Reader PAXSTORE UI Observation Ingest

if /I "%~1"=="/?" goto usage
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if "%~1"=="" goto usage

if not exist "%~dp0harness\api\hh_cc_reader_paxstore_ui_observation.py" (
  echo ERROR: PAXSTORE UI observation ingest seam is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER PAXSTORE UI OBSERVATION INGEST
echo ================================================================
echo  Read-only Terminal Management App ^& Firmware capture ingest.
echo  Never pushes firmware. Never invents firmware values.
echo  Installed Firmware is a distinct version domain from 2.0.15.260522.
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

%PYEXE% "%~dp0harness\api\hh_cc_reader_paxstore_ui_observation.py" %*
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   Ingest-HHCCReaderPaxstoreUiObservation.cmd --input CAPTURE.json
echo       [--expected-serial SERIAL] [--expected-mac MAC] [--live-ipv4 IPv4]
echo       [--freeze] [--compare-api API_RECEIPT.json] [--output OUT]
echo.
echo Capture JSON is a private operator artifact from Terminal Management
echo App ^& Firmware. Use --freeze to lock baseline when identity+firmware bind.
exit /b 2
