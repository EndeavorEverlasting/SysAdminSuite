@echo off
setlocal EnableExtensions
set "PACKAGE=%~dp0"
set "RUNTIME=C:\SASAL"
if not "%~1"=="" set "RUNTIME=%~1"
if "%PACKAGE:~-1%"=="\" set "PACKAGE=%PACKAGE:~0,-1%"
set "ENGINE=%PACKAGE%\Prepare-ScanSnapProtectedRuntime.ps1"
if not exist "%ENGINE%" (
  echo ERROR: ScanSnap protected-runtime preparer not found: %ENGINE%
  exit /b 1
)
echo Preparing qualified ScanSnap package for protected/offline execution...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ENGINE%" -SourcePackageRoot "%PACKAGE%" -RuntimeRoot "%RUNTIME%"
set "RC=%ERRORLEVEL%"
echo Prepare-ScanSnapProtectedRuntime exit code: %RC%
exit /b %RC%
