@echo off
setlocal EnableExtensions

set "SCRIPT=%~dp0scripts\Invoke-SasCursorWorkstation.ps1"
if not exist "%SCRIPT%" (
  echo ERROR: Cursor lifecycle engine not found: "%SCRIPT%"
  exit /b 2
)

where pwsh.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
  set "SAS_PS=pwsh.exe"
) else (
  set "SAS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
)

if "%~1"=="" (
  echo SysAdminSuite Cursor workstation lifecycle
  echo.
  echo Usage:
  echo   Manage-Cursor.cmd Audit
  echo   Manage-Cursor.cmd Verify -ExpectedState Absent
  echo   Manage-Cursor.cmd Uninstall -AllowMutation
  echo   Manage-Cursor.cmd RecoveryPurge -AllowMutation [-PurgeUserState]
  echo   Manage-Cursor.cmd InstallSystem -InstallerPath "C:\path\to\CursorSetup.exe" -AllowMutation
  echo   Manage-Cursor.cmd Verify -ExpectedState System
  echo.
  echo Read docs\CURSOR_WORKSTATION_LIFECYCLE.md before RecoveryPurge or InstallSystem.
  exit /b 2
)

"%SAS_PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "RC=%ERRORLEVEL%"
exit /b %RC%
