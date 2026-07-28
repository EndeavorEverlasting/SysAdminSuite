@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "SAS_POWERSHELL=pwsh.exe"
where %SAS_POWERSHELL% >nul 2>&1
if errorlevel 1 set "SAS_POWERSHELL=powershell.exe"
where %SAS_POWERSHELL% >nul 2>&1
if errorlevel 1 (
  echo ERROR: PowerShell 5.1 or PowerShell 7 is required.
  exit /b 9009
)

%SAS_POWERSHELL% -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Show-SasOperatorEvidence.ps1" %*
exit /b %ERRORLEVEL%
