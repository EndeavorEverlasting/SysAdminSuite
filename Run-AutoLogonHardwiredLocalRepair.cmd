@echo off
setlocal EnableExtensions DisableDelayedExpansion

if "%~1"=="" (
  echo Usage: Run-AutoLogonHardwiredLocalRepair.cmd HOST EXPECTED_COMMIT
  echo.
  echo Repairs C:\SASAL from this already-local detached worktree with no Git command,
  echo proves a DomainAuthenticated non-Wi-Fi Northwell connection, then runs the
  echo existing crash-safe AutoLogon Remote transaction.
  exit /b 2
)

if "%~2"=="" (
  echo ERROR: EXPECTED_COMMIT is required.
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
echo Source:  %SAS_ROOT%
echo Target:  %SAS_TARGET%
echo Commit:  %SAS_EXPECTED%
echo Git commands: NONE
echo Remote repository access: NONE
echo Clinical-core deployment: NONE
echo.

"%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_SCRIPT%" -ComputerName "%SAS_TARGET%" -ExpectedCommit "%SAS_EXPECTED%" -SourceRoot "%SAS_ROOT%" -ConfirmDeployment
set "SAS_RC=%ERRORLEVEL%"

echo.
echo Hardwired AutoLogon local-repair/deployment exit code: %SAS_RC%
exit /b %SAS_RC%
