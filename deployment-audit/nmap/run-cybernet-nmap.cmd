@echo off
setlocal EnableExtensions

REM Non-PowerShell workflow for Cybernet/Neuron target verification.
REM Offline workbook analysis is allowed anywhere.
REM Live probing is blocked unless the WAB network guard passes.
REM Live probing is progress-aware and writes resumable per-target logs.
REM
REM Usage:
REM   run-cybernet-nmap.cmd "C:\path\to\CybernetWorkbook.xlsx"
REM   run-cybernet-nmap.cmd "C:\path\to\CybernetWorkbook.xlsx" --fresh
REM   run-cybernet-nmap.cmd "C:\path\to\CybernetWorkbook.xlsx" --fast-stable
REM   run-cybernet-nmap.cmd "C:\path\to\CybernetWorkbook.xlsx" --fresh --fast-stable
REM   run-cybernet-nmap.cmd "C:\path\to\CybernetWorkbook.xlsx" --max-concurrency 2
REM
REM Safety rule:
REM   All modes still run the WAB guard before any live probe starts.

set "SOURCE_XLSX=%~1"
set "RUNNER_EXTRA_ARGS="
shift /1

if "%SOURCE_XLSX%"=="" (
  echo Usage: %~nx0 "C:\path\to\CybernetWorkbook.xlsx" [--fresh] [--force] [--fast-stable] [--max-concurrency N]
  exit /b 2
)

:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="--fresh" (
  set "RUNNER_EXTRA_ARGS=%RUNNER_EXTRA_ARGS% --fresh"
  shift /1
  goto parse_args
)
if /I "%~1"=="--force" (
  set "RUNNER_EXTRA_ARGS=%RUNNER_EXTRA_ARGS% --force"
  shift /1
  goto parse_args
)
if /I "%~1"=="--fast-stable" (
  set "RUNNER_EXTRA_ARGS=%RUNNER_EXTRA_ARGS% --fast-stable"
  shift /1
  goto parse_args
)
if /I "%~1"=="--max-concurrency" (
  if "%~2"=="" (
    echo Missing value for --max-concurrency
    exit /b 2
  )
  set "RUNNER_EXTRA_ARGS=%RUNNER_EXTRA_ARGS% --max-concurrency %~2"
  shift /1
  shift /1
  goto parse_args
)
if /I "%~1"=="--analysis-interval" (
  if "%~2"=="" (
    echo Missing value for --analysis-interval
    exit /b 2
  )
  set "RUNNER_EXTRA_ARGS=%RUNNER_EXTRA_ARGS% --analysis-interval %~2"
  shift /1
  shift /1
  goto parse_args
)
if /I "%~1"=="--heartbeat-interval" (
  if "%~2"=="" (
    echo Missing value for --heartbeat-interval
    exit /b 2
  )
  set "RUNNER_EXTRA_ARGS=%RUNNER_EXTRA_ARGS% --heartbeat-interval %~2"
  shift /1
  shift /1
  goto parse_args
)
echo Invalid option: %~1
echo Allowed options: --fresh, --force, --fast-stable, --max-concurrency N, --analysis-interval N, --heartbeat-interval N
exit /b 2

:args_done
set "SCRIPT_DIR=%~dp0"
set "OUT_DIR=%SCRIPT_DIR%output\cybernet-nmap-audit"
set "WAB_GUARD_CONFIG=%SCRIPT_DIR%northwell_wab_guard.local.json"
set "WAB_GUARD_EVIDENCE=%OUT_DIR%\network-guard-evidence.txt"
set "PYTHON_CMD="
set "NMAP_CMD="

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

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

echo Running offline workbook analysis...
%PYTHON_CMD% "%SCRIPT_DIR%cybernet_target_audit.py" --source-xlsx "%SOURCE_XLSX%" --out-dir "%OUT_DIR%"
if errorlevel 1 exit /b %errorlevel%

echo Checking approved Northwell WAB network before live probe...
if exist "%WAB_GUARD_CONFIG%" (
  %PYTHON_CMD% "%SCRIPT_DIR%northwell_wab_guard.py" --config "%WAB_GUARD_CONFIG%" --write-evidence "%WAB_GUARD_EVIDENCE%"
) else (
  %PYTHON_CMD% "%SCRIPT_DIR%northwell_wab_guard.py" --write-evidence "%WAB_GUARD_EVIDENCE%"
)
if errorlevel 1 (
  echo Live probe skipped. This machine did not pass the approved WAB network guard.
  echo Offline reports are still available in: "%OUT_DIR%"
  echo Network evidence saved to: "%WAB_GUARD_EVIDENCE%"
  exit /b 0
)

where nmap >nul 2>nul
if not errorlevel 1 set "NMAP_CMD=nmap"
if "%NMAP_CMD%"=="" if exist "%ProgramFiles(x86)%\Nmap\nmap.exe" set "NMAP_CMD=%ProgramFiles(x86)%\Nmap\nmap.exe"
if "%NMAP_CMD%"=="" if exist "%ProgramFiles%\Nmap\nmap.exe" set "NMAP_CMD=%ProgramFiles%\Nmap\nmap.exe"
if "%NMAP_CMD%"=="" if exist "C:\Program Files (x86)\Nmap\nmap.exe" set "NMAP_CMD=C:\Program Files (x86)\Nmap\nmap.exe"
if "%NMAP_CMD%"=="" if exist "C:\Program Files\Nmap\nmap.exe" set "NMAP_CMD=C:\Program Files\Nmap\nmap.exe"

if "%NMAP_CMD%"=="" (
  echo Nmap was not found. Live probe skipped.
  exit /b 0
)

echo Runner options:%RUNNER_EXTRA_ARGS%
echo Running progress-aware live probe from approved WAB network...
%PYTHON_CMD% "%SCRIPT_DIR%nmap_probe_runner.py" --source-xlsx "%SOURCE_XLSX%" --out-dir "%OUT_DIR%" --nmap-exe "%NMAP_CMD%" %RUNNER_EXTRA_ARGS%
exit /b %errorlevel%
