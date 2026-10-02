@echo off
setlocal EnableExtensions
title SysAdminSuite - H^&H CC Reader Estate Packet Normalize ^(P5-B^)

if /I "%~1"=="/?" goto usage
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage

if not exist "%~dp0harness\api\hh_cc_reader_estate_packet_normalize.py" (
  echo ERROR: P5-B packet normalizer is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER ESTATE PACKET NORMALIZE ^(P5-B^)
echo ================================================================
echo  Populate settled/derivable packet fields only.
echo  Never invent live firmware/package/release values.
echo  No Payment Fusion / PAXSTORE / network contact.
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

if "%~1"=="" (
  if not defined TEMP (
    echo ERROR: TEMP is undefined and no packet path was provided.
    exit /b 2
  )
  %PYEXE% "%~dp0harness\api\hh_cc_reader_estate_packet_normalize.py" --output "%TEMP%\hh-cc-p5-packet-fill.json" --worksheet "%TEMP%\hh-cc-p5-c-operator-worksheet.md"
  exit /b %ERRORLEVEL%
)

%PYEXE% "%~dp0harness\api\hh_cc_reader_estate_packet_normalize.py" %*
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   Normalize-HHCCReaderEstatePacket.cmd
echo   Normalize-HHCCReaderEstatePacket.cmd --output PACKET_OUT [--worksheet MD] [PACKET_IN]
echo.
echo Default no-arg form writes:
echo   %%TEMP%%\hh-cc-p5-packet-fill.json
echo   %%TEMP%%\hh-cc-p5-c-operator-worksheet.md
echo from the repository template when PACKET_IN is omitted.
exit /b 2
