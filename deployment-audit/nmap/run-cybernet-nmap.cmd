@echo off
setlocal EnableExtensions

REM Non-PowerShell Nmap workflow for Cybernet/Neuron target verification.
REM Usage:
REM   run-cybernet-nmap.cmd "C:\path\to\cybernet 5.21.xlsx"

set "SOURCE_XLSX=%~1"
if "%SOURCE_XLSX%"=="" (
  echo Usage: %~nx0 "C:\path\to\CybernetWorkbook.xlsx"
  exit /b 2
)

set "SCRIPT_DIR=%~dp0"
set "OUT_DIR=%SCRIPT_DIR%output\cybernet-nmap-audit"
set "NMAP_XML=%OUT_DIR%\nmap-discovery.xml"
set "PYTHON_CMD="
set "NMAP_CMD="

where python >nul 2>nul
if not errorlevel 1 set "PYTHON_CMD=python"

if "%PYTHON_CMD%"=="" (
  where py >nul 2>nul
  if not errorlevel 1 set "PYTHON_CMD=py"
)

if "%PYTHON_CMD%"=="" (
  echo Python was not found.
  echo Install Python 3 from https://www.python.org/downloads/windows/
  echo During install, check: Add python.exe to PATH
  echo Then close and reopen Command Prompt and rerun this command.
  exit /b 2
)

where nmap >nul 2>nul
if not errorlevel 1 set "NMAP_CMD=nmap"

if "%NMAP_CMD%"=="" if exist "%ProgramFiles(x86)%\Nmap\nmap.exe" set "NMAP_CMD=%ProgramFiles(x86)%\Nmap\nmap.exe"
if "%NMAP_CMD%"=="" if exist "%ProgramFiles%\Nmap\nmap.exe" set "NMAP_CMD=%ProgramFiles%\Nmap\nmap.exe"
if "%NMAP_CMD%"=="" if exist "C:\Program Files (x86)\Nmap\nmap.exe" set "NMAP_CMD=C:\Program Files (x86)\Nmap\nmap.exe"
if "%NMAP_CMD%"=="" if exist "C:\Program Files\Nmap\nmap.exe" set "NMAP_CMD=C:\Program Files\Nmap\nmap.exe"

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

%PYTHON_CMD% "%SCRIPT_DIR%cybernet_target_audit.py" --source-xlsx "%SOURCE_XLSX%" --out-dir "%OUT_DIR%"
if errorlevel 1 exit /b %errorlevel%

if "%NMAP_CMD%"=="" (
  echo Nmap was not found in PATH or the normal install folders.
  echo Install Nmap, add nmap.exe to PATH, or run this manually using your full nmap.exe path:
  echo nmap -sn -n --reason -iL "%OUT_DIR%\targets.txt" -oX "%NMAP_XML%"
  exit /b 0
)

echo Running host discovery scan from generated target list...
"%NMAP_CMD%" -sn -n --reason -iL "%OUT_DIR%\targets.txt" -oX "%NMAP_XML%"
if errorlevel 1 exit /b %errorlevel%

echo Matching Nmap XML results back to source inventory...
%PYTHON_CMD% "%SCRIPT_DIR%cybernet_target_audit.py" --source-xlsx "%SOURCE_XLSX%" --out-dir "%OUT_DIR%" --nmap-xml "%NMAP_XML%" --fail-on-duplicates
exit /b %errorlevel%
