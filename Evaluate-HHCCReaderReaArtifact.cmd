@echo off
setlocal EnableExtensions DisableDelayedExpansion
title SysAdminSuite - H^&H CC Reader REA Offline Artifact Analysis

if "%~1"=="" goto usage
if /I "%~1"=="/?" goto usage
if not exist "%~dp0harness\api\hh_cc_reader_rea_bridge.py" (
  echo ERROR: REA bridge is missing beside the canonical SysAdminSuite launcher.
  exit /b 2
)
if not defined LOCALAPPDATA (
  echo ERROR: LOCALAPPDATA is unavailable; cannot write a private receipt.
  exit /b 2
)
set "OUTDIR=%LOCALAPPDATA%\SysAdminSuite\cc-reader\rea"
if not exist "%OUTDIR%" mkdir "%OUTDIR%"
if not exist "%OUTDIR%" (
  echo ERROR: Unable to create private receipt directory.
  exit /b 2
)
set "PYEXE="
where py >nul 2>&1 && set "PYEXE=py -3"
if not defined PYEXE where python >nul 2>&1 && set "PYEXE=python"
if not defined PYEXE (
  echo ERROR: Python 3 is required.
  exit /b 2
)
set "ACTION=%~2"
if "%ACTION%"=="" goto plan
if /I "%ACTION%"=="plan" goto plan
if /I "%ACTION%"=="inspect" goto inspect
if /I "%ACTION%"=="extract" goto extract
goto usage

:plan
%PYEXE% "%~dp0harness\api\hh_cc_reader_rea_bridge.py" --input "%~1" --output "%OUTDIR%"
exit /b %ERRORLEVEL%

:inspect
%PYEXE% "%~dp0harness\api\hh_cc_reader_rea_bridge.py" --input "%~1" --output "%OUTDIR%" --invoke
exit /b %ERRORLEVEL%

:extract
if "%~3"=="" goto usage
%PYEXE% "%~dp0harness\api\hh_cc_reader_rea_bridge.py" --input "%~1" --output "%OUTDIR%" --invoke --extract-output "%~3"
exit /b %ERRORLEVEL%

:usage
echo H^&H CC Reader REA: LOCAL artifact analysis ONLY. Reader never contacted.
echo Usage:
echo   Evaluate-HHCCReaderReaArtifact.cmd PRIVATE_MANIFEST.json plan
echo   Evaluate-HHCCReaderReaArtifact.cmd PRIVATE_MANIFEST.json inspect
echo   Evaluate-HHCCReaderReaArtifact.cmd PRIVATE_MANIFEST.json extract NEW_PRIVATE_OUTPUT_DIR
echo.
echo Requires separately installed/approved REA and its per-target prerequisites.
echo Never uploads/installs firmware, edits reader partitions, or changes payment state.
exit /b 2
