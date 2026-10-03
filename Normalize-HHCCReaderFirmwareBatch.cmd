@echo off
setlocal EnableExtensions
title SysAdminSuite - H^&H CC Reader Firmware Batch Normalize

if /I "%~1"=="/?" goto usage
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if "%~1"=="" goto usage

if not exist "%~dp0harness\api\hh_cc_reader_firmware_roundtrip.py" (
  echo ERROR: firmware round-trip seam is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER FIRMWARE BATCH NORMALIZE
echo ================================================================
echo  Normalize dashboard/CSV batch rows into a fail-closed plan.
echo  Does not mutate readers. Does not invent identity/firmware.
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

set "INPUT=%~1"
set "OUT="
set "SERIAL="
shift
:parse
if "%~1"=="" goto run
if /I "%~1"=="--output" (
  set "OUT=%~2"
  shift
  shift
  goto parse
)
if /I "%~1"=="--execute-serial" (
  set "SERIAL=%~2"
  shift
  shift
  goto parse
)
echo ERROR: unknown argument %~1
exit /b 2

:run
if defined OUT (
  if defined SERIAL (
    %PYEXE% "%~dp0harness\api\hh_cc_reader_firmware_roundtrip.py" batch --input "%INPUT%" --output "%OUT%" --execute-serial "%SERIAL%"
  ) else (
    %PYEXE% "%~dp0harness\api\hh_cc_reader_firmware_roundtrip.py" batch --input "%INPUT%" --output "%OUT%"
  )
) else (
  if defined SERIAL (
    %PYEXE% "%~dp0harness\api\hh_cc_reader_firmware_roundtrip.py" batch --input "%INPUT%" --execute-serial "%SERIAL%"
  ) else (
    %PYEXE% "%~dp0harness\api\hh_cc_reader_firmware_roundtrip.py" batch --input "%INPUT%"
  )
)
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   Normalize-HHCCReaderFirmwareBatch.cmd CSV_OR_JSON [--output OUT] [--execute-serial SERIAL]
echo.
echo Example CSV: docs\examples\hh-cc-reader-firmware-batch.example.csv
echo --execute-serial restricts executable rows to one validated device.
exit /b 2
