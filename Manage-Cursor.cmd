@echo off
setlocal EnableExtensions

set "SCRIPT=%~dp0scripts\Invoke-SasCursorWorkstation.ps1"
if not exist "%SCRIPT%" (
  echo ERROR: Cursor read-only lifecycle engine not found: "%SCRIPT%"
  exit /b 2
)

if "%~1"=="" goto usage
if /I "%~1"=="Audit" goto run
if /I "%~1"=="Verify" goto run

echo ERROR: Cursor mutation is intentionally unavailable on this safety floor.
echo Supported actions: Audit, Verify
echo Read docs\CURSOR_WORKSTATION_LIFECYCLE.md for the blocked mutation gates.
exit /b 3

:run
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
  set "SAS_PS=pwsh.exe"
) else (
  set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
)
"%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
exit /b %ERRORLEVEL%

:usage
echo SysAdminSuite Cursor workstation read-only safety floor
echo.
echo Usage:
echo   Manage-Cursor.cmd Audit
echo   Manage-Cursor.cmd Verify -ExpectedState Absent
echo   Manage-Cursor.cmd Verify -ExpectedState System
echo.
echo InstallSystem, Uninstall, and RecoveryPurge are intentionally disabled.
exit /b 2
