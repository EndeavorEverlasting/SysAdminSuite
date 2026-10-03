@echo off
setlocal EnableExtensions EnableDelayedExpansion
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
set "SERIAL_SET=0"
shift

:parse
if "%~1"=="" goto run
if /I "%~1"=="--output" (
  if "%~2"=="" (
    echo ERROR: --output requires a non-empty path value.
    endlocal & exit /b 2
  )
  set "OUT=%~2"
  shift
  shift
  goto parse
)
if /I "%~1"=="--execute-serial" (
  if "%~2"=="" (
    echo ERROR: --execute-serial requires a non-empty serial value.
    endlocal & exit /b 2
  )
  set "SERIAL=%~2"
  set "SERIAL_SET=1"
  shift
  shift
  goto parse
)
echo ERROR: unknown argument %~1
endlocal & exit /b 2

:run
if not exist "%INPUT%" (
  echo ERROR: input file not found: %INPUT%
  exit /b 2
)

if defined OUT (
  if "!SERIAL_SET!"=="1" (
    %PYEXE% "%~dp0harness\api\hh_cc_reader_firmware_roundtrip.py" batch --input "%INPUT%" --output "%OUT%" --execute-serial "%SERIAL%"
  ) else (
    %PYEXE% "%~dp0harness\api\hh_cc_reader_firmware_roundtrip.py" batch --input "%INPUT%" --output "%OUT%"
  )
) else (
  if "!SERIAL_SET!"=="1" (
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
echo --execute-serial requires a non-empty validated serial.
echo --output requires a non-empty path when supplied.
exit /b 2
