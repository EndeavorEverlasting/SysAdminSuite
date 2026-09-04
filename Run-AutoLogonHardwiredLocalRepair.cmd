@echo off
setlocal EnableExtensions DisableDelayedExpansion

if "%~1"=="" (
  echo Usage: Run-AutoLogonHardwiredLocalRepair.cmd HOST EXPECTED_COMMIT
  echo.
  echo Use only when this exact clean local checkout already contains EXPECTED_COMMIT
  echo and the Admin Box is on an approved DomainAuthenticated non-Wi-Fi Northwell path.
  exit /b 2
)
if "%~2"=="" (
  echo ERROR: EXPECTED_COMMIT is required.
  exit /b 2
)
if not "%~3"=="" (
  echo ERROR: This command accepts exactly HOST and EXPECTED_COMMIT.
  exit /b 2
)

set "SAS_TARGET=%~1"
set "SAS_EXPECTED=%~2"
set "SAS_ROOT=%~dp0"
if "%SAS_ROOT:~-1%"=="\" set "SAS_ROOT=%SAS_ROOT:~0,-1%"
set "SAS_SCRIPT=%SAS_ROOT%\scripts\Invoke-SasAutoLogonHardwiredLocalRepair.ps1"
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%SAS_SCRIPT%" (
  echo ERROR: hardwired local-repair script is missing:
  echo   %SAS_SCRIPT%
  exit /b 3
)
if not exist "%SAS_PS%" (
  echo ERROR: Windows PowerShell 5.1 was not found:
  echo   %SAS_PS%
  exit /b 4
)

echo.
echo === SYSADMINSUITE HARDWIRED AUTOLOGON LOCAL REPAIR ===
echo Source: %SAS_ROOT%
echo Target: %SAS_TARGET%
echo Commit: %SAS_EXPECTED%
echo Remote repository acquisition: NONE
echo Runtime transfer: LOCAL FILESYSTEM ONLY
echo Clinical-core deployment: NONE

echo.
"%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_SCRIPT%" -ComputerName "%SAS_TARGET%" -ExpectedCommit "%SAS_EXPECTED%" -SourceRoot "%SAS_ROOT%" -ConfirmDeployment
set "SAS_RC=%ERRORLEVEL%"

echo.
echo Hardwired AutoLogon local-repair/deployment exit code: %SAS_RC%
endlocal & exit /b %SAS_RC%
