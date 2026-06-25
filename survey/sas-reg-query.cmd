@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem SysAdminSuite Northwell registry evidence collector
rem Read-only helper. Uses reg.exe QUERY only.
rem This script does not install software, write registry values, use credentials, or change target state.

set "TARGET=localhost"
set "OUTPUT_DIR=survey\output\registry-evidence"
set "SOFTWARE_ID=unspecified-software"
set "CUSTOM_KEY="

:parse
if "%~1"=="" goto parsed
if /I "%~1"=="--target" (
  set "TARGET=%~2"
  shift
  shift
  goto parse
)
if /I "%~1"=="--output-dir" (
  set "OUTPUT_DIR=%~2"
  shift
  shift
  goto parse
)
if /I "%~1"=="--software-id" (
  set "SOFTWARE_ID=%~2"
  shift
  shift
  goto parse
)
if /I "%~1"=="--custom-key" (
  set "CUSTOM_KEY=%~2"
  shift
  shift
  goto parse
)
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
echo [sas-reg-query] ERROR: unknown argument %~1 1>&2
exit /b 2

:usage
echo SysAdminSuite registry evidence collector
echo.
echo Usage:
echo   survey\sas-reg-query.cmd --target HOST --software-id sample-viewer --output-dir survey\output\registry-evidence
echo.
echo Safety:
echo   Read-only. Uses reg.exe QUERY only. Does not install software or modify registry.
exit /b 0

:parsed
if "%TARGET%"=="" set "TARGET=localhost"
if "%SOFTWARE_ID%"=="" set "SOFTWARE_ID=unspecified-software"
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%" >nul 2>nul

set "SAFE_TARGET=%TARGET%"
set "SAFE_TARGET=%SAFE_TARGET:\=_%"
set "SAFE_TARGET=%SAFE_TARGET:/=_%"
set "SAFE_TARGET=%SAFE_TARGET::=_%"
set "SAFE_TARGET=%SAFE_TARGET: =_%"

set "SAFE_SOFTWARE=%SOFTWARE_ID%"
set "SAFE_SOFTWARE=%SAFE_SOFTWARE:\=_%"
set "SAFE_SOFTWARE=%SAFE_SOFTWARE:/=_%"
set "SAFE_SOFTWARE=%SAFE_SOFTWARE::=_%"
set "SAFE_SOFTWARE=%SAFE_SOFTWARE: =_%"

set "OUT=%OUTPUT_DIR%\%SAFE_TARGET%_%SAFE_SOFTWARE%_registry_raw.txt"

if /I "%TARGET%"=="localhost" (
  set "ROOT=HKLM"
) else if /I "%TARGET%"=="." (
  set "ROOT=HKLM"
) else (
  set "ROOT=\\%TARGET%\HKLM"
)

> "%OUT%" echo # SysAdminSuite registry evidence raw output
>> "%OUT%" echo # target=%TARGET%
>> "%OUT%" echo # software_id=%SOFTWARE_ID%
>> "%OUT%" echo # command_family=reg_query_read_only
>> "%OUT%" echo # note=OS and endpoint telemetry may record this read-only query activity.
>> "%OUT%" echo.

>> "%OUT%" echo ### UNINSTALL_64
reg.exe QUERY "%ROOT%\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" /s >> "%OUT%" 2>>&1
>> "%OUT%" echo.
>> "%OUT%" echo ### UNINSTALL_32
reg.exe QUERY "%ROOT%\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" /s >> "%OUT%" 2>>&1

if not "%CUSTOM_KEY%"=="" (
  >> "%OUT%" echo.
  >> "%OUT%" echo ### CUSTOM_KEY
  reg.exe QUERY "%ROOT%\%CUSTOM_KEY%" /s >> "%OUT%" 2>>&1
)

echo %OUT%
endlocal
exit /b 0
