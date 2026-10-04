@echo off
setlocal EnableExtensions
title SysAdminSuite - H^&H CC Reader PAXSTORE Terminal Observe

if /I "%~1"=="/?" goto usage
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if "%~1"=="" goto usage

if not exist "%~dp0harness\api\hh_cc_reader_paxstore_terminal_observe.py" (
  echo ERROR: PAXSTORE terminal observe seam is missing beside this launcher.
  exit /b 1
)

echo ================================================================
echo  SYSADMINSUITE H^&H CC READER PAXSTORE TERMINAL OBSERVE
echo ================================================================
echo  Read-only getTerminalBySn + includeInstalledFirmware.
echo  Credentials: SAS_PAXSTORE_API_KEY / SAS_PAXSTORE_API_SECRET
echo  Optional: SAS_PAXSTORE_BASE_URL
echo  Never pushes firmware. Never invents firmware values.
echo  firmwareName is a distinct version domain from 2.0.15.260522.
echo ================================================================
echo.

cd /d "%~dp0"

set "PYEXE="
where py >nul 2>&1 && set "PYEXE=py -3"
if not defined PYEXE where python >nul 2>&1 && set "PYEXE=python"
if not defined PYEXE (
  echo ERROR: Python 3 is required ^(py -3 or python on PATH^).
  exit /b 1
)

%PYEXE% "%~dp0harness\api\hh_cc_reader_paxstore_terminal_observe.py" %*
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   Observe-HHCCReaderPaxstoreTerminal.cmd --serial SERIAL [--expected-mac MAC]
echo       [--live-ipv4 IPv4] [--freeze] [--fixture JSON] [--output OUT]
echo.
echo Without API credentials the seam fails closed:
echo   CREDENTIAL_GATE when estate rights are external/unowned
echo   AUTHORIZED_ACCESS_SETUP_REQUIRED when SAS_PAXSTORE_ESTATE_AUTHORITY=OWNED_ADMINISTERING
echo Use --fixture for offline contract proof. Live reads require ESI keys.
exit /b 2
