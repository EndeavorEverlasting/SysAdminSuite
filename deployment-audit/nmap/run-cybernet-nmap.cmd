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

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

python "%SCRIPT_DIR%cybernet_target_audit.py" --source-xlsx "%SOURCE_XLSX%" --out-dir "%OUT_DIR%"
if errorlevel 1 exit /b %errorlevel%

where nmap >nul 2>nul
if errorlevel 1 (
  echo Nmap was not found in PATH. Install Nmap or add nmap.exe to PATH, then rerun the command below:
  echo nmap -sn -n --reason -iL "%OUT_DIR%\targets.txt" -oX "%NMAP_XML%"
  exit /b 0
)

echo Running host discovery scan from generated target list...
nmap -sn -n --reason -iL "%OUT_DIR%\targets.txt" -oX "%NMAP_XML%"
if errorlevel 1 exit /b %errorlevel%

echo Matching Nmap XML results back to source inventory...
python "%SCRIPT_DIR%cybernet_target_audit.py" --source-xlsx "%SOURCE_XLSX%" --out-dir "%OUT_DIR%" --nmap-xml "%NMAP_XML%" --fail-on-duplicates
exit /b %errorlevel%
