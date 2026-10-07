@echo off
setlocal EnableExtensions
title SysAdminSuite - H^&H CC Reader Capability Program

if /I "%~1"=="/?" goto usage
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage

if not exist "%~dp0harness\api\hh_cc_reader_capability_orchestrator.py" (
  echo ERROR: Capability orchestrator seam is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER CAPABILITY PROGRAM
echo ================================================================
echo  Topology-aware DAG. Attended gates do not stop independent work.
echo  High-cost Admin Box relocation is last resort.
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

%PYEXE% "%~dp0harness\api\hh_cc_reader_capability_orchestrator.py" %*
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   Evaluate-HHCCReaderCapabilityProgram.cmd --mode run --topology PROFILE [--operator-presence none^|optional^|required]
echo   Evaluate-HHCCReaderCapabilityProgram.cmd --mode ledger^|attended-manifest^|catalog^|classify-result
echo.
echo Topology profiles include DESK_COMPUTER_AVAILABLE and LAB_READER_ON_NETWORK_OPERATOR_ABSENT.
exit /b 2
