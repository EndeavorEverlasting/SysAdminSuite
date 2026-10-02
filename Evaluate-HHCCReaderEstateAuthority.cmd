@echo off
setlocal EnableExtensions
title SysAdminSuite - H^&H CC Reader Estate Authority Evaluate

if "%~1"=="" goto usage
if /I "%~1"=="/?" goto usage
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage

if not exist "%~1" (
  echo ERROR: packet file not found: %~1
  echo Provide one sanitized authority packet JSON path outside Git when needed.
  exit /b 2
)

if not exist "%~dp0harness\api\hh_cc_reader_estate_authority.py" (
  echo ERROR: estate-authority evaluator is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER ESTATE AUTHORITY EVALUATE
echo ================================================================
echo  Local offline evaluation of one sanitized P5 authority packet.
echo  No Payment Fusion / PAXSTORE / network contact.
echo  Mutation remains unauthorized even after PROVEN_PATH.
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

%PYEXE% "%~dp0harness\api\hh_cc_reader_estate_authority.py" "%~1"
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   Evaluate-HHCCReaderEstateAuthority.cmd SANITIZED_PACKET_JSON
echo.
echo Example:
echo   Evaluate-HHCCReaderEstateAuthority.cmd %%TEMP%%\hh-cc-p5-packet-fill.json
echo.
echo The packet JSON must contain evaluator_inputs for the canonical
echo harness\api\hh_cc_reader_estate_authority.py evaluate^(^) seam.
exit /b 2
