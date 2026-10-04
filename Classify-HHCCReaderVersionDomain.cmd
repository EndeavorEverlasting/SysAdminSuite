@echo off
setlocal EnableExtensions
title SysAdminSuite - H^&H CC Reader Version Domain Classify

if /I "%~1"=="/?" goto usage
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if "%~1"=="" goto usage

if not exist "%~dp0harness\api\hh_cc_reader_version_domain.py" (
  echo ERROR: version-domain classify seam is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER VERSION DOMAIN CLASSIFY
echo ================================================================
echo  Read-only labeled observation classify.
echo  Campaign 2.0.15.260522 stays VERSION_DOMAIN_UNRESOLVED until labeled bind.
echo  Never invents domains from numeric similarity alone.
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

%PYEXE% "%~dp0harness\api\hh_cc_reader_version_domain.py" %*
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   Classify-HHCCReaderVersionDomain.cmd --input CAPTURE_OR_OBSERVATIONS.json [--output OUT]
echo.
echo Prefer labeled_observations with section/field_heading/value.
exit /b 2
