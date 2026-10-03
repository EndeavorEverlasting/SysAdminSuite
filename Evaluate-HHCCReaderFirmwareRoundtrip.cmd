@echo off
setlocal EnableExtensions
title SysAdminSuite - H^&H CC Reader Firmware Round-Trip Evaluate

if /I "%~1"=="/?" goto usage
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if "%~1"=="" goto usage
if "%~2"=="" goto usage

if not exist "%~dp0harness\api\hh_cc_reader_firmware_roundtrip.py" (
  echo ERROR: firmware round-trip seam is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER FIRMWARE ROUND-TRIP EVALUATE
echo ================================================================
echo  Offline identity / baseline / restore / eligibility / preview /
echo  compare contracts only. Never invents live values.
echo  No Payment Fusion / PAXSTORE / reader mutation.
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

%PYEXE% "%~dp0harness\api\hh_cc_reader_firmware_roundtrip.py" %*
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   Evaluate-HHCCReaderFirmwareRoundtrip.cmd MODE --input JSON [--output OUT]
echo.
echo Modes: identity ^| baseline ^| restore ^| eligibility ^| preview ^| compare ^| batch
echo Never authorizes firmware mutation. Missing baseline / identity fails closed.
exit /b 2
