@echo off
setlocal EnableExtensions DisableDelayedExpansion

if "%~1"=="" (
  echo Usage: Complete-SysAdminSuiteAutoLogon.cmd HOST
  echo.
  echo Verifies the sealed runtime, runs one fresh read-only Kerberos SMB/task preflight,
  echo and enters the existing crash-safe AutoLogon deployment only when transport is ready.
  exit /b 2
)
if not "%~2"=="" (
  echo ERROR: This command accepts exactly one authorized HOST.
  exit /b 2
)

set "SAS_TARGET=%~1"
set "SAS_RUNTIME=%~dp0"
if "%SAS_RUNTIME:~-1%"=="\" set "SAS_RUNTIME=%SAS_RUNTIME:~0,-1%"
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SAS_COMPLETION=%SAS_RUNTIME%\scripts\Invoke-SasAutoLogonCompletion.ps1"

if not exist "%SAS_PS%" (
  echo ERROR: Windows PowerShell 5.1 was not found at:
  echo   %SAS_PS%
  exit /b 3
)
if not exist "%SAS_COMPLETION%" (
  echo ERROR: AutoLogon completion gate is missing:
  echo   %SAS_COMPLETION%
  echo Run sas refresh on Guest/Internet before protected deployment.
  exit /b 4
)

echo.
echo === SYSADMINSUITE AUTOLOGON COMPLETION GATE ===
echo Runtime: %SAS_RUNTIME%
echo Target:  %SAS_TARGET%
echo Git network activity: NONE
echo Preflight mutation authority: NONE
echo Deployment authority: existing sealed crash-safe bootstrap only after fresh transport admission

echo.
"%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_COMPLETION%" -ComputerName "%SAS_TARGET%" -RuntimeRoot "%SAS_RUNTIME%" -PreflightTimeoutSeconds 15
set "SAS_RC=%ERRORLEVEL%"

echo.
echo AutoLogon completion exit code: %SAS_RC%
endlocal & exit /b %SAS_RC%
