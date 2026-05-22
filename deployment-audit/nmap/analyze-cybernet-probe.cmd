@echo off
setlocal EnableExtensions

REM Analyze completed per-target probe XML/logs after a premature stop.
REM This does not run a live probe.

set "SOURCE_XLSX=%~1"
if "%SOURCE_XLSX%"=="" (
  echo Usage: %~nx0 "C:\path\to\CybernetWorkbook.xlsx"
  exit /b 2
)

set "SCRIPT_DIR=%~dp0"
set "OUT_DIR=%SCRIPT_DIR%output\cybernet-nmap-audit"
set "PYTHON_CMD="

where python >nul 2>nul
if not errorlevel 1 set "PYTHON_CMD=python"

if "%PYTHON_CMD%"=="" (
  where py >nul 2>nul
  if not errorlevel 1 set "PYTHON_CMD=py"
)

if "%PYTHON_CMD%"=="" (
  echo Python was not found. Install Python 3 and make sure python.exe is in PATH.
  exit /b 2
)

%PYTHON_CMD% "%SCRIPT_DIR%nmap_probe_runner.py" --source-xlsx "%SOURCE_XLSX%" --out-dir "%OUT_DIR%" --analyze-only
exit /b %errorlevel%
