@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
echo SysAdminSuite - Auto Didact Install
echo Snapshot protocol: BEFORE snapshot - plan/install - AFTER snapshot
echo Evidence: survey\output\autodidact_install
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Start-SasAutoDidactInstall.ps1" -Action Menu %*
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" echo Auto Didact install workflow failed or was cancelled. Review the console output and survey\output\autodidact_install.
endlocal & exit /b %EXITCODE%
