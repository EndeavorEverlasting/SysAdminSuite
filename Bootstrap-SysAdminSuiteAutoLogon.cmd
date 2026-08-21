@echo off
setlocal EnableExtensions DisableDelayedExpansion

if "%~1"=="" (
  echo Usage: Bootstrap-SysAdminSuiteAutoLogon.cmd HOST [EXPECTED_PREPARED_COMMIT] [LEGACY_EVIDENCE_ROOT]
  echo.
  echo Runs the protected SysAdminSuite AutoLogon bootstrap under Windows PowerShell 5.1.
  echo The runtime must already be sealed by sas refresh on Guest/Internet.
  echo EXPECTED_PREPARED_COMMIT is optional but recommended for a pinned field attempt.
  echo LEGACY_EVIDENCE_ROOT is optional and used only when explicitly supplied.
  echo The explicit HOST argument authorizes only that one remote target for this process tree.
  exit /b 2
)

set "SAS_TARGET=%~1"
set "SAS_EXPECTED=%~2"
set "SAS_LEGACY=%~3"
set "SAS_RUNTIME=%~dp0"
if "%SAS_RUNTIME:~-1%"=="\" set "SAS_RUNTIME=%SAS_RUNTIME:~0,-1%"
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SAS_MANIFEST_RESOLVER=%SAS_RUNTIME%\scripts\Resolve-SasAutoLogonManifestAuthority.ps1"
set "SAS_AUDIT=%SAS_RUNTIME%\scripts\Test-SasAutoLogonRuntimeSeal.ps1"
set "SAS_BOOTSTRAP=%SAS_RUNTIME%\Bootstrap-SysAdminSuiteAutoLogon.ps1"
set "SAS_EXPLICIT_REMOTE_TARGET_REQUEST=%SAS_TARGET%"

if not exist "%SAS_PS%" (
  echo ERROR: Windows PowerShell 5.1 was not found at:
  echo   %SAS_PS%
  exit /b 3
)

if not exist "%SAS_MANIFEST_RESOLVER%" (
  echo ERROR: AutoLogon manifest authority resolver is missing:
  echo   %SAS_MANIFEST_RESOLVER%
  echo No crash-safe AutoLogon field transaction was started.
  exit /b 4
)

if not exist "%SAS_AUDIT%" (
  echo ERROR: AutoLogon runtime seal audit is missing:
  echo   %SAS_AUDIT%
  echo No crash-safe AutoLogon field transaction was started.
  exit /b 4
)

if not exist "%SAS_BOOTSTRAP%" (
  echo ERROR: Canonical AutoLogon bootstrap is missing:
  echo   %SAS_BOOTSTRAP%
  echo No crash-safe AutoLogon field transaction was started.
  exit /b 4
)

echo.
echo === SYSADMINSUITE PROTECTED AUTOLOGON BOOTSTRAP ===
echo Runtime: %SAS_RUNTIME%
echo Target:  %SAS_TARGET%
echo Engine:  Windows PowerShell 5.1
if defined SAS_EXPECTED echo Expected prepared commit: %SAS_EXPECTED%
echo Git network activity: NONE
echo Target authority: explicit one-target operator command
echo.

echo === RESOLVING SEALED MANIFEST AUTHORITY - NO TARGET CONTACT ===
if defined SAS_EXPECTED (
  "%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_MANIFEST_RESOLVER%" -RuntimeRoot "%SAS_RUNTIME%" -ExpectedCommit "%SAS_EXPECTED%" -RequireManifest
) else (
  "%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_MANIFEST_RESOLVER%" -RuntimeRoot "%SAS_RUNTIME%" -RequireManifest
)
set "SAS_MANIFEST_RC=%ERRORLEVEL%"
if not "%SAS_MANIFEST_RC%"=="0" (
  echo.
  echo AutoLogon manifest authority resolution exit code: %SAS_MANIFEST_RC%
  echo Deployment blocked before runtime audit and crash-safe field transaction.
  exit /b %SAS_MANIFEST_RC%
)

echo.
echo === FULL SEALED RUNTIME AUDIT - NO TARGET CONTACT ===
if defined SAS_EXPECTED (
  "%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_AUDIT%" -RuntimeRoot "%SAS_RUNTIME%" -ExpectedCommit "%SAS_EXPECTED%"
) else (
  "%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_AUDIT%" -RuntimeRoot "%SAS_RUNTIME%"
)
set "SAS_AUDIT_RC=%ERRORLEVEL%"
if not "%SAS_AUDIT_RC%"=="0" (
  echo.
  echo AutoLogon runtime seal audit exit code: %SAS_AUDIT_RC%
  echo Deployment blocked before crash-safe field transaction.
  exit /b %SAS_AUDIT_RC%
)

echo.
echo === SEALED RUNTIME AUDIT PASSED - ENTERING PROTECTED BOOTSTRAP ===
if defined SAS_EXPECTED (
  "%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_BOOTSTRAP%" -ComputerName "%SAS_TARGET%" -RuntimeRoot "%SAS_RUNTIME%" -LegacyEvidenceRoot "%SAS_LEGACY%" -ExpectedCommit "%SAS_EXPECTED%" -ConfirmVpnPosture
) else (
  "%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_BOOTSTRAP%" -ComputerName "%SAS_TARGET%" -RuntimeRoot "%SAS_RUNTIME%" -LegacyEvidenceRoot "%SAS_LEGACY%" -ConfirmVpnPosture
)

set "SAS_RC=%ERRORLEVEL%"
echo.
echo AutoLogon bootstrap exit code: %SAS_RC%
exit /b %SAS_RC%
