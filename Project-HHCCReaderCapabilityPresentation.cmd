@echo off
setlocal EnableExtensions
title SysAdminSuite - H^&H CC Reader Capability Presentation Projection

if /I "%~1"=="/?" goto usage
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if "%~1"=="" goto usage

if not exist "%~dp0harness\api\hh_cc_reader_capability_presentation.py" (
  echo ERROR: Presentation projection seam is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER PRESENTATION PROJECTION
echo ================================================================
echo  Evidence-driven views only. Does not mutate the executive deck.
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

%PYEXE% "%~dp0harness\api\hh_cc_reader_capability_presentation.py" %*
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   Project-HHCCReaderCapabilityPresentation.cmd --ledger LEDGER.json [--output OUT]
exit /b 2
