@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "SCRIPT_DIR=%~dp0"
set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SAS_REFRESH=%SCRIPT_DIR%scripts\Refresh-SasOperatorCommand.ps1"
set "SAS_UNIVERSAL_INSTALLER=C:\SASAL\scripts\Install-SasUniversalFieldLauncher.ps1"

if /I "%~1"=="Help" goto help_ok
if /I "%~1"=="-h" goto help_ok
if /I "%~1"=="--help" goto help_ok
if /I "%~1"=="/?" goto help_ok
if not "%~1"=="" goto help_error

if not exist "%SAS_PS%" (
  echo ERROR: Windows PowerShell 5.1 was not found at:
  echo   %SAS_PS%
  exit /b 3
)
if not exist "%SAS_REFRESH%" (
  echo ERROR: Current SysAdminSuite refresh workflow is missing:
  echo   %SAS_REFRESH%
  exit /b 4
)

echo.
echo === SYSADMINSUITE FIELD RUNTIME BOOTSTRAP ===
echo NETWORK REQUIRED: GUEST / INTERNET
 echo VPN posture: disconnected before repository synchronization
 echo Source checkout: %SCRIPT_DIR%
echo Existing Desktop/OneDrive checkouts are not reset, cleaned, or reused as deployment authority.
echo.

"%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_REFRESH%" -RepositoryRoot "%SCRIPT_DIR%"
set "SAS_REFRESH_RC=%ERRORLEVEL%"
if not "%SAS_REFRESH_RC%"=="0" (
  echo.
  echo Field runtime refresh stopped with exit code %SAS_REFRESH_RC%.
  echo No protected target deployment was started.
  exit /b %SAS_REFRESH_RC%
)

if not exist "%SAS_UNIVERSAL_INSTALLER%" (
  echo ERROR: Refreshed sealed runtime is missing the universal field installer:
  echo   %SAS_UNIVERSAL_INSTALLER%
  echo Remain on GUEST / INTERNET and repair the refresh before target work.
  exit /b 20
)

"%SAS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SAS_UNIVERSAL_INSTALLER%"
set "SAS_INSTALL_RC=%ERRORLEVEL%"
if not "%SAS_INSTALL_RC%"=="0" (
  echo.
  echo Universal sas installation stopped with exit code %SAS_INSTALL_RC%.
  echo No protected target deployment was started.
  exit /b %SAS_INSTALL_RC%
)

echo.
echo SAS_FIELD_RUNTIME_BOOTSTRAP_READY
echo Sealed runtime: C:\SASAL
echo Next network for deployment: PROTECTED NORTHWELL
echo Open a NEW terminal after changing network and run:
echo   sas cybernet Deploy HOST
exit /b 0

:help_ok
call :print_help
exit /b 0

:help_error
call :print_help
exit /b 2

:print_help
echo SysAdminSuite Guest field-runtime bootstrap
echo.
echo Usage:
echo   Bootstrap-SysAdminSuiteFieldRuntime.cmd
echo.
echo Run only on GUEST / INTERNET with the protected VPN disconnected. The command refreshes the isolated sync cache, stages and seals C:\SASAL from current repository truth, and installs the universal sas front door. It does not contact or mutate a field target.
exit /b 0
