@echo off
setlocal EnableExtensions
title SysAdminSuite - H^&H CC Reader Firmware Evidence Event Export

if /I "%~1"=="/?" goto usage
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if "%~1"=="" goto usage

if not exist "%~dp0harness\api\hh_cc_reader_firmware_event.py" (
  echo ERROR: firmware evidence event producer is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER FIRMWARE EVIDENCE EVENT EXPORT
echo ================================================================
echo  Deterministic hh-cc-reader-firmware-event/v1 from SAS receipts.
echo  Offline. No tracker / Google Drive / OneDrive / mutation.
echo  Does not invent firmware or strengthen proof ceilings.
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

%PYEXE% "%~dp0harness\api\hh_cc_reader_firmware_event.py" %*
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   Export-HHCCReaderFirmwareEvent.cmd --input BUNDLE_JSON [--output OUT]
echo.
echo Bundle JSON contains canonical SAS receipt objects ^(identity, baseline,
echo restore_path, compare, post_update, post_rollback, final_runtime^).
echo Never authorizes firmware mutation. Publication systems are not contacted.
exit /b 2
