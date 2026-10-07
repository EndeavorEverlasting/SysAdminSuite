@echo off
setlocal EnableExtensions
title SysAdminSuite - H^&H CC Reader Firmware Portability Classifier

if /I "%~1"=="/?" goto usage
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if "%~1"=="" goto usage

if not exist "%~dp0harness\api\hh_cc_reader_firmware_source_portability.py" (
  echo ERROR: Firmware portability classifier is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER FIRMWARE PORTABILITY
echo ================================================================
echo  Classifies artifact, provenance, portability, and apply mechanism.
echo  Does not preapprove or blanket-reject reader-derived firmware.
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

%PYEXE% "%~dp0harness\api\hh_cc_reader_firmware_source_portability.py" %*
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   Classify-HHCCReaderFirmwarePortability.cmd --input DESCRIPTOR.json [--output OUT]
exit /b 2
