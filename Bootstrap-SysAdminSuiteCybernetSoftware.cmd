@echo off
setlocal EnableExtensions DisableDelayedExpansion

if /I "%~1"=="Help" goto help_ok
if /I "%~1"=="-h" goto help_ok
if /I "%~1"=="--help" goto help_ok
if /I "%~1"=="/?" goto help_ok

if "%~1"=="" goto help_error
if not "%~3"=="" goto help_error

set "SAS_TARGET=%~1"
set "SAS_EXPECTED=%~2"
set "SAS_RUNTIME=%~dp0"
if "%SAS_RUNTIME:~-1%"=="\" set "SAS_RUNTIME=%SAS_RUNTIME:~0,-1%"
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SAS_MANIFEST_RESOLVER=%SAS_RUNTIME%\scripts\Resolve-SasAutoLogonManifestAuthority.ps1"
set "SAS_AUDIT=%SAS_RUNTIME%\scripts\Test-SasAutoLogonRuntimeSeal.ps1"
set "SAS_ENGINE=%SAS_RUNTIME%\scripts\Invoke-SasCybernetSoftwareDeployment.ps1"

if not exist "%SAS_PS%" (
  echo ERROR: Windows PowerShell 5.1 was not found at:
  echo   %SAS_PS%
  exit /b 3
)
if not exist "%SAS_MANIFEST_RESOLVER%" goto runtime_missing
if not exist "%SAS_AUDIT%" goto runtime_missing
if not exist "%SAS_ENGINE%" goto runtime_missing

echo.
echo === SYSADMINSUITE SEALED CYBERNET SOFTWARE BOOTSTRAP ===
echo Runtime: %SAS_RUNTIME%
echo Target:  %SAS_TARGET%
echo Engine:  Windows PowerShell 5.1
if defined SAS_EXPECTED echo Expected prepared commit: %SAS_EXPECTED%
echo Git network activity: NONE
echo Target contact before seal audit: NONE
echo Target mutation before seal audit: NONE
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
  echo Cybernet manifest authority resolution exit code: %SAS_MANIFEST_RC%
  echo Deployment blocked before runtime audit and target contact.
  echo Return to GUEST / INTERNET with VPN disconnected and run: sas refresh
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
  echo Cybernet runtime seal audit exit code: %SAS_AUDIT_RC%
  echo Deployment blocked before target contact.
  echo Return to GUEST / INTERNET with VPN disconnected and run: sas refresh
  exit /b %SAS_AUDIT_RC%
)

echo.
echo === SEALED RUNTIME VERIFIED - ENTERING CYBERNET DEPLOYMENT ===
"%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_ENGINE%" -ComputerName "%SAS_TARGET%" -AllowTargetMutation -ConfirmDeployment
set "SAS_RC=%ERRORLEVEL%"
echo.
echo Cybernet software deployment exit code: %SAS_RC%
if not "%SAS_RC%"=="0" echo Run: sas evidence Cybernet Open
exit /b %SAS_RC%

:runtime_missing
echo ERROR: The sealed Cybernet deployment runtime is incomplete under:
echo   %SAS_RUNTIME%
echo Return to GUEST / INTERNET with VPN disconnected and run: sas refresh
echo No target contact or mutation was started.
exit /b 20

:help_ok
call :print_help
exit /b 0

:help_error
call :print_help
exit /b 2

:print_help
echo SysAdminSuite sealed Cybernet software bootstrap
echo.
echo Usage:
echo   Bootstrap-SysAdminSuiteCybernetSoftware.cmd HOST [EXPECTED_PREPARED_COMMIT]
echo.
echo This protected-network bootstrap verifies the Guest-staged manifest and complete SHA-256 runtime seal before any target contact, then runs the canonical full Cybernet software deployment. It performs no Git network operation.
echo.
echo Normal technician command after Guest refresh:
echo   sas cybernet Deploy HOST
echo.
echo Required terminal success:
echo   CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED
exit /b 0
