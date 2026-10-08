@echo off
setlocal EnableExtensions
if "%~1"=="" goto usage
if /I "%~1"=="--help" goto usage
if not exist "%~dp0harness\api\android_provider_cli.py" exit /b 2
set "PYEXE="
where py >nul 2>&1 && set "PYEXE=py -3"
if not defined PYEXE where python >nul 2>&1 && set "PYEXE=python"
if not defined PYEXE (
  echo BLOCK: Python 3 is required in the prepared management runtime.
  exit /b 2
)
%PYEXE% "%~dp0harness\api\android_provider_cli.py" %*
exit /b %ERRORLEVEL%
:usage
echo SysAdminSuite AndroidProvider - typed operations, private local receipts
echo Operations: status doctor prepare verify probe inventory tcpip-cert stop-server last-result
echo Preparation requires --role, --archive and --archive-sha256.
echo Inventory requires --identity-file. TCP certification also requires --authorize-transport.
echo No public download, arbitrary shell, firmware or debugging enablement.
exit /b 2
