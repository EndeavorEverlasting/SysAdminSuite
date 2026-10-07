@echo off
setlocal EnableExtensions
title SysAdminSuite - H^&H CC Reader PAXSTORE Firmware Adapter

if /I "%~1"=="/?" goto usage
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if "%~1"=="" goto usage

if not exist "%~dp0harness\api\hh_cc_reader_paxstore_terminal_firmware.py" (
  echo ERROR: PAXSTORE firmware adapter is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER PAXSTORE FIRMWARE ADAPTER
echo ================================================================
echo  Default mode is observe/preview. Push is fail-closed.
echo  Credentials: SAS_PAXSTORE_API_KEY / SAS_PAXSTORE_API_SECRET
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

%PYEXE% "%~dp0harness\api\hh_cc_reader_paxstore_terminal_firmware.py" %*
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   Preview-HHCCReaderPaxstoreFirmware.cmd --mode preview --serial SERIAL --fm-name NAME [--observe-fixture JSON]
echo   Preview-HHCCReaderPaxstoreFirmware.cmd --mode history^|task-status^|push^|post-verify^|observe ...
echo.
echo Push requires --allow-mutation and SAS_PAXSTORE_FIRMWARE_MUTATION_AUTHORITY=EXPLICIT_FIRMWARE_PUSH_AUTHORIZED.
exit /b 2
