@echo off
setlocal EnableExtensions DisableDelayedExpansion

if "%~1"=="" (
  echo Usage: Prepare-SysAdminSuiteAutoLogonCloseout.cmd HOST
  echo.
  echo Run this on Guest / ordinary Internet before switching to the protected Northwell network.
  echo It prepares and verifies a current sealed C:\SASAL runtime and writes one protected deployment handoff.
  echo It does not contact or mutate the target.
  exit /b 2
)

set "SAS_TARGET=%~1"
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SAS_SCRIPT=%~dp0Prepare-SysAdminSuiteAutoLogonCloseout.ps1"

if not exist "%SAS_PS%" (
  echo ERROR: Windows PowerShell 5.1 was not found at:
  echo   %SAS_PS%
  exit /b 3
)

if not exist "%SAS_SCRIPT%" (
  echo ERROR: AutoLogon closeout preparer is missing:
  echo   %SAS_SCRIPT%
  exit /b 4
)

"%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_SCRIPT%" -ComputerName "%SAS_TARGET%"
set "SAS_RC=%ERRORLEVEL%"

exit /b %SAS_RC%
