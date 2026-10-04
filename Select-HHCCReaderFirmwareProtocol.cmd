@echo off
setlocal EnableExtensions
title SysAdminSuite - H^&H CC Reader Firmware Protocol Select

if "%~1"=="" goto usage
if /I "%~1"=="/?" goto usage
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage

if not exist "%~1" (
  echo ERROR: selection context JSON not found: %~1
  exit /b 2
)

if not exist "%~dp0harness\api\hh_cc_reader_firmware_protocols.py" (
  echo ERROR: firmware protocol selector is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER FIRMWARE PROTOCOL SELECT
echo ================================================================
echo  Selects and dispatches the next READ-ONLY observation route.
echo  All configured protocols remain preserved as candidates.
echo  Protocol selection NEVER authorizes firmware mutation.
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

%PYEXE% "%~dp0harness\api\hh_cc_reader_firmware_protocols.py" dispatch --input "%~1"
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   Select-HHCCReaderFirmwareProtocol.cmd CONTEXT_JSON
echo.
echo The context must contain only sanitized evidence/authority/gate signals
echo plus an optional proven H^&H site_profile object. The selector is
echo read-only and always returns mutation_authorized=false.
exit /b 2
