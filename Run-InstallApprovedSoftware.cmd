@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
echo SysAdminSuite - Approved Software Install
echo Catalog: Epic, BCA, AllScripts, AutoLogon
echo Snapshot protocol: BEFORE snapshot - plan/install - AFTER snapshot
echo Evidence: survey\output\approved_software_install
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Start-SasApprovedSoftwareOperator.ps1" -Action Menu %*
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Approved software workflow failed or was cancelled. Review the console and survey\output\approved_software_install.
endlocal & exit /b %EXITCODE%
