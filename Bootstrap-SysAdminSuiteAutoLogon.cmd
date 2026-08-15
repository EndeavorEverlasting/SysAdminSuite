@echo off
setlocal EnableExtensions DisableDelayedExpansion

if "%~1"=="" (
  echo Usage: Bootstrap-SysAdminSuiteAutoLogon.cmd HOST [EXPECTED_PREPARED_COMMIT] [LEGACY_EVIDENCE_ROOT]
  echo.
  echo Runs the protected SysAdminSuite AutoLogon bootstrap under Windows PowerShell 5.1.
  echo The runtime must already be sealed by sas refresh on Guest/Internet.
  echo EXPECTED_PREPARED_COMMIT is optional but recommended for a pinned field attempt.
  echo LEGACY_EVIDENCE_ROOT is optional and used only when explicitly supplied.
  echo The bootstrap authorizes only the canonical resolved FQDN after protected-network admission.
  exit /b 2
)

set "SAS_TARGET=%~1"
set "SAS_EXPECTED=%~2"
set "SAS_LEGACY=%~3"
set "SAS_RUNTIME=%~dp0"
if "%SAS_RUNTIME:~-1%"=="\" set "SAS_RUNTIME=%SAS_RUNTIME:~0,-1%"
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SAS_BOOTSTRAP=%SAS_RUNTIME%\Bootstrap-SysAdminSuiteAutoLogon.ps1"

if not exist "%SAS_PS%" (
  echo ERROR: Windows PowerShell 5.1 was not found at:
  echo   %SAS_PS%
  exit /b 3
)

if not exist "%SAS_BOOTSTRAP%" (
  echo ERROR: Canonical AutoLogon bootstrap is missing:
  echo   %SAS_BOOTSTRAP%
  exit /b 4
)

echo.
echo === SYSADMINSUITE PROTECTED AUTOLOGON BOOTSTRAP ===
echo Runtime: %SAS_RUNTIME%
echo Target:  %SAS_TARGET%
echo Engine:  Windows PowerShell 5.1
if defined SAS_EXPECTED echo Expected prepared commit: %SAS_EXPECTED%
echo Git network activity: NONE
echo.

if defined SAS_EXPECTED (
  "%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_BOOTSTRAP%" -ComputerName "%SAS_TARGET%" -RuntimeRoot "%SAS_RUNTIME%" -LegacyEvidenceRoot "%SAS_LEGACY%" -ExpectedCommit "%SAS_EXPECTED%" -ConfirmLocalTargetAuthorization -ConfirmVpnPosture
) else (
  "%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_BOOTSTRAP%" -ComputerName "%SAS_TARGET%" -RuntimeRoot "%SAS_RUNTIME%" -LegacyEvidenceRoot "%SAS_LEGACY%" -ConfirmLocalTargetAuthorization -ConfirmVpnPosture
)

set "SAS_RC=%ERRORLEVEL%"
echo.
echo AutoLogon bootstrap exit code: %SAS_RC%
exit /b %SAS_RC%
