@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SAS_EXIT=1"
if "%~1"=="" goto usage
if /I "%~1"=="Audit" goto freshness
if /I "%~1"=="Verify" goto freshness

echo ERROR: Cursor mutation is intentionally unavailable on this safety floor.
echo Supported actions: Audit, Verify
echo Read docs\CURSOR_WORKSTATION_LIFECYCLE.md for the blocked mutation gates.
set "SAS_EXIT=3"
goto finish

:freshness
if defined SAS_CURSOR_AUDIT_REFRESHED goto run
if not exist "%~dp0scripts\Invoke-SasNetworkAwareField.ps1" (
  echo ERROR: Canonical SysAdminSuite refresh entrypoint is missing beside this CMD.
  echo Run a current machine-neutral SysAdminSuite bootstrap before Cursor audit.
  set "SAS_EXIT=1"
  goto finish
)

echo Proving current SysAdminSuite main before Cursor inventory...
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-SasNetworkAwareField.ps1" refresh
set "SAS_EXIT=!ERRORLEVEL!"
if not "!SAS_EXIT!"=="0" goto finish

if not exist "C:\SASAL\Manage-Cursor.cmd" (
  echo ERROR: Refresh completed but the sealed runtime does not contain C:\SASAL\Manage-Cursor.cmd.
  set "SAS_EXIT=1"
  goto finish
)
set "SAS_CURSOR_AUDIT_REFRESHED=1"
call "C:\SASAL\Manage-Cursor.cmd" %*
set "SAS_EXIT=!ERRORLEVEL!"
goto finish

:run
set "SCRIPT=%~dp0scripts\Invoke-SasCursorWorkstation.ps1"
if not exist "%SCRIPT%" (
  echo ERROR: Refreshed Cursor read-only lifecycle engine not found: "%SCRIPT%"
  set "SAS_EXIT=2"
  goto finish
)
where pwsh.exe >nul 2>&1
if !ERRORLEVEL! EQU 0 (
  set "SAS_PS=pwsh.exe"
) else (
  set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
)
"!SAS_PS!" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "SAS_EXIT=!ERRORLEVEL!"
goto finish

:usage
echo SysAdminSuite Cursor workstation read-only safety floor
echo.
echo Usage:
echo   Manage-Cursor.cmd Audit
echo   Manage-Cursor.cmd Verify -ExpectedState Absent
echo   Manage-Cursor.cmd Verify -ExpectedState System
echo.
echo InstallSystem, Uninstall, and RecoveryPurge are intentionally disabled.
set "SAS_EXIT=2"

:finish
endlocal & exit /b %SAS_EXIT%
