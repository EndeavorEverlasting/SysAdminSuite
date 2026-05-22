@echo off
setlocal EnableExtensions

REM Non-PowerShell workflow for Cybernet/Neuron target verification.
REM Offline workbook analysis is allowed anywhere.
REM Live Nmap probing is blocked unless the WAB network guard passes.

set "SOURCE_XLSX=%~1"
if "%SOURCE_XLSX%"=="" (
  echo Usage: %~nx0 "C:\path\to\CybernetWorkbook.xlsx"
  exit /b 2
)

set "SCRIPT_DIR=%~dp0"
set "OUT_DIR=%SCRIPT_DIR%output\cybernet-nmap-audit"
set "NMAP_XML=%OUT_DIR%\nmap-discovery.xml"
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

echo Running live probe from approved WAB network...
"%NMAP_CMD%" -sn -n --reason -iL "%OUT_DIR%\targets.txt" -oX "%NMAP_XML%"
if errorlevel 1 exit /b %errorlevel%

echo Matching live probe XML back to source inventory...
%PYTHON_CMD% "%SCRIPT_DIR%cybernet_target_audit.py" --source-xlsx "%SOURCE_XLSX%" --out-dir "%OUT_DIR%" --nmap-xml "%NMAP_XML%" --fail-on-duplicates
exit /b %errorlevel%
