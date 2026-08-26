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
set "SAS_CANONICAL_RUNTIME=C:\SASAL"
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SAS_BOOTSTRAP=%SAS_CANONICAL_RUNTIME%\scripts\Invoke-SasCybernetSealedSoftwareBootstrap.ps1"

if /I not "%SAS_RUNTIME%"=="%SAS_CANONICAL_RUNTIME%" (
  echo CYBERNET_SEALED_RUNTIME_AUTHORITY_INVALID
  echo ERROR: Protected Cybernet deployment may run only from the canonical sealed runtime:
  echo   %SAS_CANONICAL_RUNTIME%
  echo Invoked copy:
  echo   %SAS_RUNTIME%
  echo No manifest resolution, target contact, or mutation was started.
  echo Return to GUEST / INTERNET with VPN disconnected and run: sas refresh
  exit /b 21
)

if not exist "%SAS_PS%" (
  echo ERROR: Windows PowerShell 5.1 was not found at:
  echo   %SAS_PS%
  exit /b 3
)
if not exist "%SAS_BOOTSTRAP%" (
  echo ERROR: The sealed Cybernet deployment admission script is missing:
  echo   %SAS_BOOTSTRAP%
  echo Return to GUEST / INTERNET with VPN disconnected and run: sas refresh
  echo No target contact or mutation was started.
  exit /b 20
)

set "SAS_CYBERNET_EXPLICIT_TARGET=%SAS_TARGET%"
set "SAS_CYBERNET_EXPECTED_COMMIT=%SAS_EXPECTED%"

echo.
echo === SYSADMINSUITE SEALED CYBERNET SOFTWARE BOOTSTRAP ===
echo Runtime authority: %SAS_CANONICAL_RUNTIME%
echo Target: %SAS_TARGET%
echo Engine: Windows PowerShell 5.1
echo Git network activity: NONE
if defined SAS_EXPECTED echo Expected prepared commit: %SAS_EXPECTED%
echo.

if defined SAS_EXPECTED (
  "%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& 'C:\SASAL\scripts\Invoke-SasCybernetSealedSoftwareBootstrap.ps1' -ComputerName $env:SAS_CYBERNET_EXPLICIT_TARGET -RuntimeRoot 'C:\SASAL' -ExpectedCommit $env:SAS_CYBERNET_EXPECTED_COMMIT"
) else (
  "%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& 'C:\SASAL\scripts\Invoke-SasCybernetSealedSoftwareBootstrap.ps1' -ComputerName $env:SAS_CYBERNET_EXPLICIT_TARGET -RuntimeRoot 'C:\SASAL'"
)
set "SAS_RC=%ERRORLEVEL%"
echo.
echo Cybernet sealed deployment exit code: %SAS_RC%
if not "%SAS_RC%"=="0" echo Run: sas evidence Cybernet Open
exit /b %SAS_RC%

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
echo This command is valid only when its own normalized directory is exactly C:\SASAL. The PowerShell admission layer resolves the Guest-staged manifest, audits the complete SHA-256 seal, locks and re-hashes every tracked runtime file against writes/deletes, and keeps those locks until the full Cybernet deployment returns.
echo.
echo Normal technician command after Guest refresh:
echo   sas cybernet Deploy HOST
echo.
echo Required terminal success:
echo   CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED
exit /b 0
