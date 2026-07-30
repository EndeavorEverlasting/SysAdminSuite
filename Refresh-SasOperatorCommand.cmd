@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "SAS_POWERSHELL=powershell.exe"
where %SAS_POWERSHELL% >nul 2>&1
if errorlevel 1 (
  echo ERROR: Windows PowerShell 5.1 is required.
  exit /b 9009
)

%SAS_POWERSHELL% -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Refresh-SasOperatorCommand.ps1" -RepositoryRoot "%~dp0"
set "EXITCODE=%ERRORLEVEL%"
endlocal & exit /b %EXITCODE%
